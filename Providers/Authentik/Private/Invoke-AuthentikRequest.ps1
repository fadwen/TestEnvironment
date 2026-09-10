function Invoke-AuthentikRequest {
    <#
    .SYNOPSIS
        Sends one request to the Authentik API, with paging, retry and a readable error

    .DESCRIPTION
        The single path every Authentik call takes. Authentik's API is a Django REST Framework
        application under /api/v3, which fixes three things this function has to know:

        - Listings are paginated by page number. A page carries its results under 'results'
          and a 'pagination' object whose 'next' is the next page number, or 0 on the last
          page. With -Paginate this follows that number until it runs out and returns the
          flattened results; without it the page is returned as the server sent it.
        - Errors are JSON. A generic failure carries 'detail'; a validation failure carries one
          array of messages per field, or 'non_field_errors'. Get-AuthentikErrorDetail turns
          either into one line, and that line is what the thrown exception says.
        - Rate limiting answers 429 with a Retry-After header in seconds. That is honoured,
          capped, and otherwise backed off exponentially, as is anything 5xx.

        The response is decoded from its raw bytes as UTF-8 rather than trusting the charset
        Windows PowerShell infers, because the seed data carries accented names on purpose and
        Latin-1 decoding turns every one of them into mojibake.

    .PARAMETER Method
        HTTP method. PATCH is included because Authentik updates are partial by convention.

    .PARAMETER Path
        The path under /api/v3, with a leading slash and Authentik's trailing slash, for
        example '/core/users/'.

    .PARAMETER Body
        A hashtable or object to send as JSON, or a string sent as-is.

    .PARAMETER Query
        Query string parameters. Null and empty values are dropped rather than sent.

    .PARAMETER Paginate
        Follow the page numbers and return every result across all pages.

    .PARAMETER Connection
        A connection to use instead of the active one. Tests pass one; the service account
        bootstrap passes the one it is in the middle of proving.

    .PARAMETER MaxRetry
        Attempts before a 429 or 5xx is reported as a failure.

    .OUTPUTS
        System.Object. The deserialised page, or with -Paginate an array of every result.

    .EXAMPLE
        PS> Invoke-AuthentikRequest -Method GET -Path '/core/users/' -Query @{ path = 'zz-test' } -Paginate

        DESCRIPTION: Lists every user under the seed path across all pages
        OUTPUT: An array of user objects
        USE CASE: Ownership discovery before teardown

    .EXAMPLE
        PS> Invoke-AuthentikRequest -Method POST -Path '/core/groups/' -Body @{ name = 'ZZ-TEST-All Staff' }

        DESCRIPTION: Creates a group
        OUTPUT: The group as Authentik stored it, including its pk
        USE CASE: Every create in the seed

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [hashtable]$Connection,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetry = 5
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }

    # Windows PowerShell defaults to TLS 1.0. Only ever add to the enabled set: clearing it
    # would change behaviour for everything else in the session.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $baseUri = '{0}/api/v3{1}' -f $Connection.BaseUrl.TrimEnd('/'), $Path

    # Page numbers are a query parameter, so the query is rebuilt per page rather than a
    # next-URL being followed. page_size is raised from the default 20 to keep the number of
    # round trips proportionate to a few hundred objects.
    $queryPairs = @{}
    if ($Query) {
        foreach ($key in $Query.Keys) {
            if ($null -eq $Query[$key] -or '' -eq $Query[$key]) { continue }
            $queryPairs[$key] = [string]$Query[$key]
        }
    }
    if ($Paginate -and -not $queryPairs.ContainsKey('page_size')) { $queryPairs['page_size'] = '100' }

    $headers = @{ 'Accept' = 'application/json' }
    if (-not [string]::IsNullOrWhiteSpace($Connection.AuthorizationHeader)) {
        $headers['Authorization'] = $Connection.AuthorizationHeader
    }

    $bodyBytes = $null
    if ($null -ne $Body) {
        $bodyText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
    }

    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $collected = [System.Collections.Generic.List[object]]::new()
    $result = $null

    try {
        $page = 1
        while ($true) {
            if ($Paginate) { $queryPairs['page'] = [string]$page }

            $uri = $baseUri
            if ($queryPairs.Count -gt 0) {
                $pairs = foreach ($key in ($queryPairs.Keys | Sort-Object)) {
                    '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString($queryPairs[$key])
                }
                $uri = '{0}?{1}' -f $baseUri, ($pairs -join '&')
            }

            $attempt = 0
            $response = $null

            while ($true) {
                $attempt++
                try {
                    $requestArgs = @{
                        Uri             = $uri
                        Method          = $Method
                        Headers         = $headers
                        UseBasicParsing = $true
                        ErrorAction     = 'Stop'
                    }
                    if ($null -ne $bodyBytes) {
                        $requestArgs.Body = $bodyBytes
                        $requestArgs.ContentType = 'application/json; charset=UTF-8'
                    }

                    Write-Verbose "Authentik $Method $uri (attempt $attempt)"
                    $response = Invoke-WebRequest @requestArgs
                    break
                }
                catch {
                    $statusCode = 0
                    if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
                    }

                    $retryable = ($statusCode -eq 429 -or $statusCode -ge 500)
                    if (-not $retryable -or $attempt -ge $MaxRetry) {
                        # Built into a variable first. A concatenation written inline inside
                        # New-Object's argument list binds as one array argument, and the
                        # exception is then constructed with the message alone and no
                        # InnerException.
                        $statusText = if ($statusCode) { " with HTTP $statusCode" } else { '' }
                        $message = "Authentik $Method $Path failed${statusText}: " +
                            (Get-AuthentikErrorDetail -ErrorRecord $_)

                        throw (New-Object System.Exception($message, $_.Exception))
                    }

                    $waitSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
                    try {
                        $retryAfter = $_.Exception.Response.Headers['Retry-After']
                        if ($retryAfter) {
                            $fromHeader = [int](@($retryAfter)[0])
                            if ($fromHeader -gt 0) { $waitSeconds = [Math]::Min(60, $fromHeader) }
                        }
                    }
                    catch {
                        Write-Verbose 'No usable Retry-After header; backing off instead.'
                    }

                    Write-Warning ("Authentik returned HTTP $statusCode for $Method $Path. " +
                        "Retrying in $waitSeconds second(s) (attempt $attempt of $MaxRetry).")
                    Start-Sleep -Seconds $waitSeconds
                }
            }

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

            $parsed = $null
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $parsed = $content | ConvertFrom-Json
            }

            if (-not $Paginate) {
                $result = $parsed
                break
            }

            # A listing always has 'results'. Anything else under -Paginate is a caller error
            # worth failing on, not silently returning one object as a page of one.
            if (-not $parsed -or -not ($parsed.PSObject.Properties.Name -contains 'results')) {
                throw "Authentik $Method $Path did not return a paginated listing, so -Paginate does not apply."
            }

            $collected.AddRange(@($parsed.results))

            $nextPage = 0
            if ($parsed.pagination -and $parsed.pagination.next) { $nextPage = [int]$parsed.pagination.next }
            # The self-comparison is the loop guard: a server that hands back the current page
            # as the next one would otherwise never finish.
            if ($nextPage -le $page) { break }
            $page = $nextPage
        }
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    # Returned bare, deliberately. An empty array unrolls to nothing on the pipeline, and
    # every caller wraps the call in @(), which turns nothing into an empty array. Wrapping
    # it here with the comma operator instead hands @(call) a single item - the empty array
    # itself - which counts as one, and the bootstrap then refused to create an account that
    # did not exist.
    if ($Paginate) { return $collected.ToArray() }
    return $result
}
