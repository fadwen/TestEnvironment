function Invoke-EntraBatch {
    <#
    .SYNOPSIS
        Sends many Graph requests through the $batch endpoint, in chunks of twenty

    .DESCRIPTION
        Seeding at AD parity means creating roughly eleven hundred objects and wiring several
        thousand references between them. One HTTP request each would take the better part of
        an hour and burn the tenant's request quota for no reason.

        Graph's $batch endpoint takes up to twenty requests per call - verified against a live
        tenant, where a twenty-first is refused with "Number of requests inside batch exceed
        the limit" - so this chunks whatever it is given and reports per-request outcomes.

        Three things about $batch are worth knowing because none of them behaves like a normal
        call:

        - The outer call returns 200 even when every request inside it failed. The real status
          is per response, so a caller that checks only the outer result sees success while
          nothing was created.
        - Responses come back in an arbitrary order. They are correlated by the id sent with
          each request, never by position, and this function returns them keyed by the caller's
          own reference rather than by index.
        - Throttling appears per response as a 429, not as a failure of the batch. Those
          individual requests are retried in a fresh batch rather than the whole chunk being
          resent, so a single throttled request does not duplicate the nineteen that succeeded.

        Failures are reported rather than thrown. At this volume an individual failure is
        expected - a name collision, a licence refused for a user with no usage location - and
        abandoning the run over one of them leaves a half-seeded tenant that is harder to clean
        up than a complete one.

    .PARAMETER Request
        The requests to send. Each needs Reference (the caller's own key, returned with the
        result), Method, and Url relative to the API version; Body is optional.

    .PARAMETER ApiVersion
        v1.0 or beta

    .PARAMETER Activity
        Progress bar title

    .PARAMETER ShowProgress
        Draws a progress bar, since a few thousand requests is not instant

    .PARAMETER RetryOnNotFound
        Treat a 404 on an individual response as retryable. Needed whenever the batch
        references objects created moments earlier: the reference is rejected until the object
        is addressable on the replica handling it, and without this the first pass places only
        a fraction of them and reports the rest as failures.

    .PARAMETER MaxRetry
        Attempts made against a throttled or transiently failing individual request

    .PARAMETER Connection
        Connection to use instead of the module's active one

    .OUTPUTS
        EntraBatchResult[], one per request, carrying Reference, Success, Status, Body and
        Error.

    .EXAMPLE
        PS> $requests = foreach ($u in $users) {
                [PSCustomObject]@{ Reference = $u.Key; Method = 'POST'; Url = '/users'; Body = $u.Body }
            }
        PS> $results = Invoke-EntraBatch -Request $requests -ShowProgress

        DESCRIPTION: Creates every user in chunks of twenty
        OUTPUT: One result per user, correlated by its seed key
        USE CASE: Every bulk create and reference this module makes

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraBatchResult')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Request,

        [Parameter()]
        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0',

        [Parameter()]
        [string]$Activity = 'Sending Graph batch',

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$RetryOnNotFound,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RetryOnErrorMatch,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetry = 5,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }
    if (-not $Request -or $Request.Count -eq 0) { return @() }

    # Graph's own cap, verified live. Not configurable, because exceeding it is a hard error
    # rather than something to negotiate.
    $batchLimit = 20

    $results = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Request) { $pending.Add($item) }

    $attempt = 0
    $total = $pending.Count
    $completed = 0

    while ($pending.Count -gt 0 -and $attempt -lt $MaxRetry) {
        $attempt++
        $retryable = [System.Collections.Generic.List[object]]::new()

        for ($offset = 0; $offset -lt $pending.Count; $offset += $batchLimit) {
            $chunk = @($pending[$offset..([Math]::Min($offset + $batchLimit - 1, $pending.Count - 1))])

            # The id is the chunk position, not the caller's reference: Graph requires ids
            # unique within the batch and says nothing about their format, and a caller's key
            # could be anything. The mapping back is held here.
            $byId = @{}
            $requests = @(for ($i = 0; $i -lt $chunk.Count; $i++) {
                    $id = [string]$i
                    $byId[$id] = $chunk[$i]

                    $entry = [ordered]@{
                        id     = $id
                        method = $chunk[$i].Method
                        url    = $chunk[$i].Url
                    }
                    # Headers are per inner request, not per batch. A $count segment needs its
                    # own ConsistencyLevel, and a body needs its own Content-Type - the outer
                    # call's headers do not reach either.
                    $headers = @{}
                    if ($chunk[$i].PSObject.Properties['Headers'] -and $chunk[$i].Headers) {
                        foreach ($key in $chunk[$i].Headers.Keys) { $headers[$key] = $chunk[$i].Headers[$key] }
                    }
                    if ($null -ne $chunk[$i].Body) {
                        $entry.body = $chunk[$i].Body
                        # Required on any batched request carrying a body. Without it Graph
                        # rejects the inner request rather than the batch, so the failure looks
                        # like a bad payload.
                        $headers['Content-Type'] = 'application/json'
                    }
                    if ($headers.Count -gt 0) { $entry.headers = $headers }
                    $entry
                })

            $response = $null
            try {
                $response = Invoke-EntraRequest -Method POST -Path '/$batch' -ApiVersion $ApiVersion `
                    -Connection $Connection -Body @{ requests = $requests }
            }
            catch {
                # The batch call itself failed, so nothing inside it ran. Every request in the
                # chunk is retryable rather than failed.
                Write-Verbose "Batch call failed, will retry its $($chunk.Count) request(s): $($_.Exception.Message)"
                foreach ($item in $chunk) { $retryable.Add($item) }
                continue
            }

            foreach ($item in @($response.responses)) {
                $original = $byId[[string]$item.id]
                if (-not $original) {
                    Write-Warning "Batch returned a response with id '$($item.id)', which was not sent. Ignoring it."
                    continue
                }

                $status = [int]$item.status

                $errorText = $null
                if ($status -lt 200 -or $status -ge 300) {
                    $errorText = if ($item.body -and $item.body.error) {
                        '{0}: {1}' -f $item.body.error.code, $item.body.error.message
                    }
                    else { "HTTP $status" }
                }

                # Throttled or transiently failed: retried individually in a later batch, so
                # the requests that succeeded alongside it are not sent twice. A 404 counts
                # only where the caller says so - for a reference to a just-created object it
                # means the replica has not caught up, and without the retry a first pass
                # places roughly a quarter of them and reports the rest as failures.
                #
                # Some replication failures arrive as a 400 whose only signal is the message,
                # such as a just-created directory extension reporting itself "not available",
                # so the caller can name that text as retryable too.
                $retryThis = $status -eq 429 -or $status -ge 500 -or
                    ($RetryOnNotFound -and $status -eq 404) -or
                    ($RetryOnErrorMatch -and $errorText -and $status -ge 400 -and $status -lt 500 -and
                        $errorText -match $RetryOnErrorMatch)

                if ($retryThis) {
                    $retryable.Add($original)
                    continue
                }

                $succeeded = $status -ge 200 -and $status -lt 300

                $results.Add([PSCustomObject]@{
                        PSTypeName = 'EntraBatchResult'
                        Reference  = $original.Reference
                        Success    = $succeeded
                        Status     = $status
                        Body       = $item.body
                        Error      = $errorText
                    })

                $completed++
            }

            if ($ShowProgress -and $total -gt 0) {
                Write-TestProgress -Activity $Activity -Status "$completed of $total" `
                    -PercentComplete ([int](100 * [Math]::Min($completed, $total) / $total)) -ShowProgress
            }
        }

        $pending = $retryable
        if ($pending.Count -gt 0) {
            # Backoff between whole passes rather than per request. Graph throttles per
            # resource, so retrying the survivors immediately just collects more 429s.
            $wait = [Math]::Min(60, [Math]::Pow(2, $attempt))
            Write-Warning "$($pending.Count) batched request(s) were throttled or failed transiently. Retrying in $wait second(s) (pass $attempt of $MaxRetry)."
            Start-Sleep -Seconds $wait
        }
    }

    # Anything still pending exhausted the retries. Reported as failures rather than dropped,
    # so a caller counting results always gets one per request it sent.
    foreach ($item in $pending) {
        $results.Add([PSCustomObject]@{
                PSTypeName = 'EntraBatchResult'
                Reference  = $item.Reference
                Success    = $false
                Status     = 0
                Body       = $null
                Error      = "Still failing after $MaxRetry retry pass(es)"
            })
    }

    if ($ShowProgress) {
        Write-TestProgress -Activity $Activity -Completed -ShowProgress
    }

    $failed = @($results | Where-Object { -not $_.Success })
    if ($failed.Count -gt 0) {
        Write-Verbose "$($failed.Count) of $total batched request(s) failed"
    }

    return $results.ToArray()
}
