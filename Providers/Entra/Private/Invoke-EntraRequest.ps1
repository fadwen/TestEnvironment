function Invoke-EntraRequest {
    <#
    .SYNOPSIS
        Single entry point for every Microsoft Graph call this module makes

    .DESCRIPTION
        Wraps Invoke-WebRequest with the things Graph needs and PowerShell does not do by
        default:

        - Token lifecycle. The bearer token is fetched on demand and renewed before expiry,
          so no caller has to think about it. A 401 mid-run forces one renewal and retries
          once, which covers a token revoked or a clock that drifted during a long seed.
        - UTF-8 on both sides. The seed data carries accented names on purpose, and Windows
          PowerShell will otherwise send them as question marks and decode responses using
          the wrong code page.
        - @odata.nextLink pagination. Graph pages with an absolute URL rather than a cursor
          or an offset, and -Paginate follows it until it stops appearing. The link is
          compared against the URL just fetched, because a nextLink pointing at the current
          page is an infinite loop that looks like a hang.
        - Throttling. Graph answers 429 with a Retry-After in seconds. That value is
          honoured when present, with exponential backoff as the fallback, and it is capped
          so a bad header cannot park a run indefinitely.
        - Replication lag. An object created through Graph is not immediately addressable on
          every replica: a DELETE or PATCH issued seconds after the POST that created it can
          return 404. This is real and reproducible, so -RetryOnNotFound turns that specific
          case into a bounded retry rather than a spurious failure. It is opt-in, because
          for a read a 404 usually means what it says.
        - Readable errors. Graph puts the diagnosis and the request id in the response body,
          which PowerShell discards on both editions.

        Invoke-WebRequest is used rather than Invoke-RestMethod because Retry-After and the
        response status are only reachable through the response object, and Windows
        PowerShell's Invoke-RestMethod does not expose them at all.

    .PARAMETER Method
        HTTP method

    .PARAMETER Path
        Graph path below the API version, beginning with a slash, for example /users

    .PARAMETER Body
        Request body. A string is sent as-is, anything else is serialised to JSON.

    .PARAMETER Query
        Query string parameters. Values are URL-encoded. OData parameters keep their $ sign.

    .PARAMETER ApiVersion
        v1.0 or beta. Defaults to v1.0; several objects this module seeds only exist on beta.

    .PARAMETER Paginate
        Follow @odata.nextLink and return every item across all pages

    .PARAMETER ConsistencyLevel
        Sends ConsistencyLevel: eventual, which Graph requires for $count, $search and the
        advanced filter operators. Without it those queries fail rather than degrade.

    .PARAMETER RetryOnNotFound
        Treat a 404 as retryable. Use immediately after a create, where a 404 means the
        replica has not caught up rather than that the object is absent.

    .PARAMETER RetryOnErrorMatch
        Treat any 4xx whose error text matches this regular expression as retryable. Graph
        reports some replication failures as 400 rather than 404 - creating a service
        principal for an application that exists returns "does not reference a valid
        application object" with HTTP 400 - and those are indistinguishable from a genuinely
        malformed request by status code alone. Matching on the message is narrow enough to
        be safe and is the only signal available.

    .PARAMETER Connection
        Connection to use instead of the module's active one

    .PARAMETER MaxRetry
        Attempts made against a throttle, a server error, or a retryable 404

    .OUTPUTS
        The deserialised response body, the collected value array with -Paginate, or $null
        for a 204.

    .EXAMPLE
        PS> Invoke-EntraRequest -Method GET -Path '/users' -Query @{ '$select' = 'displayName' } -Paginate

        DESCRIPTION: Reads every user, following pagination
        OUTPUT: An array of user objects
        USE CASE: The read half of almost everything this module does

    .EXAMPLE
        PS> Invoke-EntraRequest -Method DELETE -Path "/groups/$id" -RetryOnNotFound

        DESCRIPTION: Deletes a group that may have been created moments ago
        OUTPUT: $null
        USE CASE: Teardown, where replication lag would otherwise look like a missing object

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0',

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [switch]$ConsistencyLevel,

        [Parameter()]
        [switch]$RetryOnNotFound,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RetryOnErrorMatch,

        [Parameter()]
        [hashtable]$Connection,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetry = 5
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }

    # Windows PowerShell defaults to TLS 1.0, which Entra refuses outright. Only ever add to
    # the enabled set: clearing it would change behaviour for everything else in the session.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $uri = '{0}/{1}{2}' -f $Connection.GraphBaseUri.TrimEnd('/'), $ApiVersion, $Path
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            if ($null -eq $Query[$key] -or '' -eq $Query[$key]) { continue }
            # The key is not escaped: OData parameters lead with a literal dollar sign, and
            # escaping it to %24 is accepted by Graph but makes every verbose trace and every
            # captured request unreadable.
            '{0}={1}' -f $key, [uri]::EscapeDataString([string]$Query[$key])
        }
        if ($pairs) { $uri = '{0}?{1}' -f $uri, ($pairs -join '&') }
    }

    $bodyBytes = $null
    if ($null -ne $Body) {
        $bodyText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
    }

    # Invoke-WebRequest paints a progress bar per call on Windows PowerShell, which across a
    # few hundred calls costs more wall clock than the calls do.
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $collected = [System.Collections.Generic.List[object]]::new()
    $result = $null

    try {
        $nextUri = $uri

        while ($nextUri) {
            $attempt = 0
            $renewed = $false
            $response = $null

            while ($true) {
                $attempt++

                $token = Get-EntraAccessToken -AsPlainText -Connection $Connection
                $headers = @{
                    'Authorization' = "Bearer $token"
                    'Accept'        = 'application/json'
                }
                if ($ConsistencyLevel) { $headers['ConsistencyLevel'] = 'eventual' }

                try {
                    $requestArgs = @{
                        Uri             = $nextUri
                        Method          = $Method
                        Headers         = $headers
                        UseBasicParsing = $true
                        ErrorAction     = 'Stop'
                    }
                    if ($null -ne $bodyBytes) {
                        $requestArgs.Body = $bodyBytes
                        $requestArgs.ContentType = 'application/json; charset=utf-8'
                    }

                    Write-Verbose "Graph $Method $nextUri (attempt $attempt)"
                    $response = Invoke-WebRequest @requestArgs
                    break
                }
                catch {
                    $statusCode = 0
                    if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
                    }

                    # One forced token renewal on a 401. Beyond that it is a real
                    # authorisation problem, and retrying only delays the message.
                    if ($statusCode -eq 401 -and -not $renewed) {
                        Write-Verbose "Graph returned 401; renewing the access token and retrying once."
                        $renewed = $true
                        $null = Get-EntraAccessToken -Force -Connection $Connection
                        continue
                    }

                    # Resolved once and reused: the message is needed both to decide whether
                    # this is retryable and to build the exception if it is not, and reading
                    # the response stream twice on Windows PowerShell yields nothing the
                    # second time.
                    $detail = Get-EntraErrorDetail -ErrorRecord $_

                    $retryable = ($statusCode -eq 429 -or $statusCode -ge 500 -or
                        ($RetryOnNotFound -and $statusCode -eq 404) -or
                        ($RetryOnErrorMatch -and $statusCode -ge 400 -and $statusCode -lt 500 -and
                            $detail -match $RetryOnErrorMatch))

                    if (-not $retryable -or $attempt -ge $MaxRetry) {
                        # The message is built into its own variable rather than inline. A
                        # concatenation written directly inside New-Object's argument list
                        # binds as ONE array argument, so ("message" + $detail), $exception
                        # is joined into a single string and matched against
                        # Exception(string). The result is a message with the inner
                        # exception's whole stack trace stringified into it, and no
                        # InnerException set at all.
                        $statusText = if ($statusCode) { " with HTTP $statusCode" } else { '' }
                        $message = "Graph $Method $ApiVersion$Path failed$statusText`: $detail"

                        throw (New-Object System.Exception($message, $_.Exception))
                    }

                    # Graph sends Retry-After in seconds on a 429. Prefer it over guessing,
                    # but cap it so a malformed header cannot park the run for an hour.
                    $waitSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
                    try {
                        $retryAfter = $_.Exception.Response.Headers['Retry-After']
                        if ($retryAfter) {
                            $parsed = 0
                            if ([int]::TryParse((@($retryAfter)[0]), [ref]$parsed) -and $parsed -gt 0) {
                                $waitSeconds = [Math]::Min(60, $parsed)
                            }
                        }
                    }
                    catch {
                        Write-Verbose "No usable Retry-After header; backing off instead."
                    }

                    Write-Warning ("Graph returned HTTP $statusCode for $Method $Path. " +
                        "Retrying in $waitSeconds second(s) (attempt $attempt of $MaxRetry).")
                    Start-Sleep -Seconds $waitSeconds
                }
            }

            # Decode from the raw bytes rather than $response.Content. Windows PowerShell
            # decodes using the response's declared charset and falls back to Latin-1, which
            # turns every accented character in the directory into mojibake.
            $content = $null
            if ($response.RawContentStream -and $response.RawContentStream.Length -gt 0) {
                $content = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
            }
            elseif ($response.Content -is [byte[]]) {
                $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
            }
            else {
                $content = [string]$response.Content
            }

            $page = $null
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $page = $content | ConvertFrom-Json
            }

            if (-not $Paginate) {
                $result = $page
                break
            }

            if ($page -and $page.PSObject.Properties['value']) {
                $items = @($page.value)
                if ($items.Count -gt 0) { $collected.AddRange($items) }
            }

            # Graph pages with an absolute URL carrying an opaque skiptoken. The
            # self-comparison is the loop guard.
            $currentUri = $nextUri
            $nextUri = $null
            if ($page -and $page.PSObject.Properties['@odata.nextLink']) {
                $link = [string]$page.'@odata.nextLink'
                if (-not [string]::IsNullOrWhiteSpace($link) -and $link -ne $currentUri) { $nextUri = $link }
            }
        }
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    if ($Paginate) { return $collected.ToArray() }
    return $result
}
