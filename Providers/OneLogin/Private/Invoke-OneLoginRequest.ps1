function Invoke-OneLoginRequest {
    <#
    .SYNOPSIS
        Calls one OneLogin API method, with pagination, token renewal, rate-limit backoff and a readable error

    .DESCRIPTION
        The single path every OneLogin call takes, and the one function the unit suite mocks.
        Nothing else in this provider touches the network except the token request and its
        revocation, which authenticate with the credential rather than a token.

        What it has to know, all of it verified against a live account:

        - A path is relative to /api/2 unless it starts with a slash, so 'users' is
          https://<subdomain>.onelogin.com/api/2/users and '/auth/rate_limit' is itself.

        - A list comes back as a bare JSON array, one page at a time. -Paginate asks for
          limit and page and keeps asking until a page comes back short or the Total-Pages
          header says there are no more. The Link header OneLogin sends is not followed: it
          names an /api/v5 path that is not the API this provider speaks.

        - The access token is renewed here, a minute before expiry, so no caller has to think
          about it. A 401 mid-run means the token was revoked or expired early, so it is renewed
          once and the call repeated before anything is thrown.

        - The account allows 5,000 calls an hour per credential. A 429 is waited out, for as long
          as the response asks up to a minute, and retried three times; a reset further away than
          that is reported rather than slept through, because a seed that stops for most of an
          hour without saying so looks hung.

        - Callers that expect a particular failure - a lookup that may find nothing, a delete of
          something already gone - name the HTTP status in -IgnoreStatus and get $null back.
          OneLogin's error names are too broad to key on: a 400 BadRequestError covers an invalid
          shortname and an empty body alike.

        Encoding, TLS and the progress bar are Invoke-TestWebRequest's job, following the HTTP
        encoding invariant in CLAUDE.md: bodies go out as UTF-8 bytes and responses are decoded from
        their raw bytes as UTF-8.

    .PARAMETER Method
        The HTTP method.

    .PARAMETER Path
        The path below /api/2, such as 'users' or 'roles/123/users', or an absolute path from
        the host when it starts with a slash.

    .PARAMETER Body
        An object serialised as JSON. Omitted for GET and DELETE.

    .PARAMETER Query
        Query string values, added to the path.

    .PARAMETER Paginate
        Ask for every page and return the items from all of them.

    .PARAMETER IgnoreStatus
        HTTP statuses to treat as an empty result rather than a failure.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        The response object, or the items from every page under -Paginate, or $null for an
        ignored status.

    .EXAMPLE
        PS> Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate

        DESCRIPTION: Reads every role, one page after another
        OUTPUT: The role objects, one by one
        USE CASE: Ownership discovery and the report

    .EXAMPLE
        PS> Invoke-OneLoginRequest -Method DELETE -Path "roles/$id" -IgnoreStatus 404

        DESCRIPTION: Deletes a role that another step may already have removed
        OUTPUT: $null when it was already gone
        USE CASE: Teardown, where a missing object is success rather than failure

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
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [int[]]$IgnoreStatus = @(),

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-OneLoginConnection }

    # Copied to locals for the $send block below, which is the only place they are read and which
    # the analyzer does not look inside when it decides whether a parameter is used.
    $requestMethod = $Method
    $requestBody = $Body
    $ignoredStatus = $IgnoreStatus

    $base = if ($Path.StartsWith('/')) { 'https://{0}{1}' -f $Connection.ApiHost, $Path }
    else { 'https://{0}/api/2/{1}' -f $Connection.ApiHost, $Path }

    $buildUri = {
        param([hashtable]$Values)
        if (-not $Values -or $Values.Count -eq 0) { return $base }
        # Sorted, so the same query always produces the same URI and a test can match it.
        $pairs = foreach ($key in ($Values.Keys | Sort-Object)) {
            '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$Values[$key])
        }
        $separator = if ($base.Contains('?')) { '&' } else { '?' }
        return '{0}{1}{2}' -f $base, $separator, ($pairs -join '&')
    }

    # One request, with the 401 renewal and the 429 backoff. Returns the response, or $null for a
    # status the caller asked to ignore.
    $send = {
        param([string]$Uri)
        $renewed = $false
        $throttled = 0
        while ($true) {
            $arguments = @{
                Method  = $requestMethod
                Uri     = $Uri
                Headers = @{ Authorization = 'Bearer {0}' -f (Get-OneLoginAccessToken -Connection $Connection -AsPlainText) }
            }
            if ($null -ne $requestBody) { $arguments['Body'] = $requestBody }

            try {
                Write-Verbose "OneLogin $Method $Uri"
                return (Invoke-TestWebRequest @arguments)
            }
            catch {
                $detail = Get-OneLoginErrorDetail -ErrorRecord $_

                if ($ignoredStatus -contains $detail.Status) {
                    Write-Verbose "OneLogin $Method $Path answered HTTP $($detail.Status), which the caller asked to ignore"
                    return $null
                }

                if ($detail.Status -eq 401 -and -not $renewed) {
                    Write-Verbose 'OneLogin refused the token; renewing it once and retrying'
                    $renewed = $true
                    $Connection.AccessToken = $null
                    continue
                }

                if ($detail.Status -eq 429 -and $throttled -lt 3) {
                    $wait = if ($detail.RetryAfterSeconds) { $detail.RetryAfterSeconds } else { 10 }
                    if ($wait -gt 60) {
                        throw ('OneLogin rate limit reached on {0} {1}: the hourly allowance resets in {2} seconds. ' +
                            'Run the step again after that; every seed step reuses what already exists.') -f $Method, $Path, $wait
                    }
                    $throttled++
                    Write-Warning "OneLogin rate limit reached; waiting $wait seconds before retrying $Method $Path"
                    Start-Sleep -Seconds $wait
                    continue
                }

                $message = 'OneLogin {0} {1} failed with HTTP {2}: {3}' -f $Method, $Path, $detail.Status, $detail.Summary
                throw (New-Object System.Exception($message, $_.Exception))
            }
        }
    }

    if (-not $Paginate) {
        $response = & $send (& $buildUri $Query)
        if ($null -eq $response -or [string]::IsNullOrWhiteSpace($response.Content)) { return $null }
        # A success is not always JSON: deleting a Smart Hook answers 202 with a word of plain text,
        # verified live. The request succeeded, so the text is handed back rather than parsed.
        $trimmed = $response.Content.TrimStart()
        if (-not ($trimmed.StartsWith('{') -or $trimmed.StartsWith('['))) { return $response.Content }
        return ($response.Content | ConvertFrom-Json)
    }

    $pageSize = $script:OneLoginPageSize
    $page = 1
    # A guard on the guard: no account this module seeds needs anywhere near this many pages, and
    # a server that ignored the page parameter would otherwise be read forever.
    $maxPages = 1000

    while ($page -le $maxPages) {
        $values = @{}
        if ($Query) { foreach ($key in $Query.Keys) { $values[$key] = $Query[$key] } }
        $values['limit'] = $pageSize
        $values['page'] = $page

        $response = & $send (& $buildUri $values)
        if ($null -eq $response -or [string]::IsNullOrWhiteSpace($response.Content)) { break }

        # Assigned before it is wrapped. Windows PowerShell's ConvertFrom-Json emits a JSON array
        # as one object, so @($content | ConvertFrom-Json) there is an array holding the array, and
        # a page of a hundred users would read as one item and end the loop.
        $parsed = $response.Content | ConvertFrom-Json
        $items = @($parsed)
        foreach ($item in $items) { if ($null -ne $item) { $item } }

        if ($items.Count -lt $pageSize) { break }
        $totalPages = 0
        if ($response.Headers -and [int]::TryParse([string]$response.Headers['Total-Pages'], [ref]$totalPages) -and
            $totalPages -gt 0 -and $page -ge $totalPages) { break }
        $page++
    }
}
