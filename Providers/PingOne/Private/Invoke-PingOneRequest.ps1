function Invoke-PingOneRequest {
    <#
    .SYNOPSIS
        Calls one PingOne management API method, with pagination, token renewal and a readable error

    .DESCRIPTION
        The single path every PingOne call takes, and the one function the unit suite mocks.
        Nothing else in this provider touches the network except the token request itself, which
        talks to a different host with a different credential.

        What it has to know:

        - A collection comes back wrapped. PingOne answers a list with `count`, `size` and an
          `_embedded` object holding one property named for the resource - `users`, `groups`,
          `populations` - so a caller that wants the items would otherwise have to know the
          property name at every call site. -Paginate unwraps it and follows `_links.next`
          until there is none, and returns the items themselves.

        - A single object is not wrapped, so it is returned as it stands.

        - The access token lives an hour. That is longer than most steps and shorter than a
          seed of any size, and the symptom of letting it lapse is a 401 halfway through a
          teardown. The token is renewed here, a minute before expiry, so no caller has to
          think about it.

        - An error carries PingOne's own shape: a `code` such as INVALID_DATA or NOT_FOUND, a
          `message`, and often a `details` array naming the offending field. The status code
          alone is close to useless - a 400 is returned for a malformed body, an unsupported
          grant type and a duplicate name alike - so the code, the message and the first detail
          are all put into the exception, along with the correlation id PingOne returns, which
          is the only thing their support can act on.

        - Callers that expect a particular failure - a show that may find nothing, a delete of
          something already gone - name the PingOne code in -IgnoreError and get $null back.
          Anything else is thrown.

        Written for Windows PowerShell 5.1 as well as 7, following the HTTP encoding invariant in
        CLAUDE.md: bodies go out as UTF-8 bytes, responses are decoded from their raw bytes as UTF-8 whatever charset they
        declare, TLS 1.2 is added on the Desktop edition, and the progress bar is suppressed. The
        Authorization header is built by hand rather than with -Authentication, and the error body
        is read from the exception response stream where ErrorDetails is empty, which is where 5.1
        leaves it.

    .PARAMETER Method
        The HTTP method.

    .PARAMETER Path
        The path below the environment, such as 'users' or 'groups/{id}/memberOfGroups'. A path
        beginning with a slash is treated as absolute below /v1, which is how the few
        organisation-scoped calls reach outside the environment.

    .PARAMETER Body
        An object serialised as JSON. Omitted for GET and DELETE.

    .PARAMETER Query
        Query string values, added to the path.

    .PARAMETER Paginate
        Follow `_links.next` and return the items from every page rather than the envelope.

    .PARAMETER IgnoreError
        PingOne error codes to treat as an empty result rather than a failure.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        The response object, or the items from every page under -Paginate, or $null for an
        ignored error.

    .EXAMPLE
        PS> Invoke-PingOneRequest -Method GET -Path 'populations' -Paginate

        DESCRIPTION: Reads every population, following pagination
        OUTPUT: The population objects themselves, not the envelope
        USE CASE: Ownership discovery and the environment report

    .EXAMPLE
        PS> Invoke-PingOneRequest -Method DELETE -Path "groups/$id" -IgnoreError 'NOT_FOUND'

        DESCRIPTION: Deletes a group that another step may already have removed
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
        [string[]]$IgnoreError = @(),

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-PingOneConnection }

    # Windows PowerShell can default to TLS 1.0, which PingOne refuses. Only ever add to the
    # enabled set: clearing it would change behaviour for everything else in the session.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $uri = if ($Path -match '^https?://') {
        $Path
    }
    elseif ($Path.StartsWith('/')) {
        'https://{0}/v1{1}' -f $Connection.ApiHost, $Path
    }
    else {
        'https://{0}/v1/environments/{1}/{2}' -f $Connection.ApiHost, $Connection.EnvironmentId, $Path
    }

    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$Query[$key])
        }
        $separator = if ($uri.Contains('?')) { '&' } else { '?' }
        $uri = '{0}{1}{2}' -f $uri, $separator, ($pairs -join '&')
    }

    # Sent as UTF-8 bytes, never as a string. Windows PowerShell 5.1 sends a string body as
    # ISO-8859-1 when the content type names no charset, whatever the machine's code page.
    # Observed against PingOne from 5.1: a plain accented é went out as the lone byte E9, which is
    # not valid UTF-8, and was stored as U+FFFD - so every accented Latin name in the directory,
    # not only the exotic ones, was corrupted. A combining accent, a Han character and an astral
    # pair, which ISO-8859-1 cannot hold at all, were each stored as '?'. Nothing failed; PingOne
    # accepted every request. A byte array is sent as it stands on both editions.
    $bodyBytes = $null
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    # Invoke-WebRequest paints a progress bar per call on Windows PowerShell, which across a few
    # hundred calls costs more wall clock than the calls do.
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $collected = [System.Collections.Generic.List[object]]::new()

    try {
        while ($true) {
            $arguments = @{
                Method          = $Method
                Uri             = $uri
                Headers         = @{
                    Authorization = 'Bearer {0}' -f (Get-PingOneAccessToken -Connection $Connection -AsPlainText)
                }
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            if ($null -ne $bodyBytes) {
                $arguments['Body'] = $bodyBytes
                $arguments['ContentType'] = 'application/json; charset=utf-8'
            }

            try {
                Write-Verbose "PingOne $Method $uri"
                $response = Invoke-WebRequest @arguments
            }
            catch {
                $detail = Get-PingOneErrorDetail -ErrorRecord $_

                if ($detail.Code -and $IgnoreError -contains $detail.Code) {
                    Write-Verbose "PingOne $Method $Path answered $($detail.Code), which the caller asked to ignore"
                    return $null
                }

                $message = 'PingOne {0} {1} failed with HTTP {2}: {3}' -f $Method, $Path, $detail.Status, $detail.Summary
                throw (New-Object System.Exception($message, $_.Exception))
            }

            # Decoded from the raw bytes as UTF-8, never from $response.Content or through
            # Invoke-RestMethod. Windows PowerShell decodes a response by its declared charset and
            # falls back to Latin-1 when there is none, which turns every accented name into
            # mojibake. PingOne declares charset=UTF-8 today, verified from 5.1, but that is a header
            # this module does not control, so the charset is not trusted.
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
            if (-not [string]::IsNullOrWhiteSpace($content)) { $page = $content | ConvertFrom-Json }

            if (-not $Paginate) { return $page }
            if ($null -eq $page) { break }

            # The envelope holds exactly one property named for the resource. Taking the first
            # rather than naming it keeps every caller from having to know the plural PingOne
            # uses, which is not always the one the path uses.
            if ($page._embedded) {
                $items = ($page._embedded.PSObject.Properties | Select-Object -First 1).Value
                foreach ($item in @($items)) { $collected.Add($item) }
            }

            $next = $null
            if ($page._links -and $page._links.next) { $next = [string]$page._links.next.href }

            # The self-comparison is the loop guard: a next link identical to the page just fetched
            # would otherwise fetch it forever.
            if (-not $next -or $next -eq $uri) { break }
            $uri = $next
        }
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    # Emitted item by item, not wrapped. A unary comma here would hand the pipeline the whole
    # array as one object: foreach over the result still works, which hides the problem, but
    # "| Where-Object name -eq ..." then sees a single item whose .name is every name at once,
    # matches it, and passes the entire collection through. Callers wanting a guaranteed array
    # wrap the call in @(), which is the ordinary idiom and the one this provider uses.
    foreach ($item in $collected) { $item }
}
