function Invoke-TestWebRequest {
    <#
    .SYNOPSIS
        The one HTTP call every REST provider makes, with the encoding Windows PowerShell gets wrong

    .DESCRIPTION
        Windows PowerShell 5.1 corrupts non-ASCII text in both directions, silently, and
        PowerShell 7 hides both faults, so a provider tested only on 7 looks correct. This is the
        one place the four things every HTTP provider needs are done, so a new provider calls it
        rather than copying them:

        - The body goes out as UTF-8 bytes. A string body is sent by 5.1 as ISO-8859-1 when the
          content type names no charset, whatever the machine's code page: against PingOne a plain
          accented e went out as the lone byte E9 and was stored as U+FFFD, and a Han character
          as '?'. A string is encoded, an object is serialised to JSON and encoded, and a byte
          array is sent as it stands.
        - The response is decoded from its raw bytes as UTF-8, never from .Content. 5.1 decodes
          by the declared charset and falls back to Latin-1; Okta declares none, and a service
          that declares UTF-8 today does so with a header this module does not control.
        - TLS 1.2 is added on the Desktop edition, which can still default to TLS 1.0. Only ever
          added to the enabled set: clearing it would change behaviour for everything else in the
          session.
        - The progress bar is suppressed, which on 5.1 costs more than the calls do, and restored
          whether the call succeeded or threw.

        What this does not do is interpret the response or the failure. The status code, headers
        and decoded text are returned for the caller to page through, and an error is left to
        propagate untouched, so a provider's error-detail function still sees the response and
        its retry logic still reads Retry-After from it.

    .PARAMETER Uri
        The full request URI.

    .PARAMETER Method
        The HTTP method.

    .PARAMETER Headers
        Request headers. Authorization and Accept belong to the caller.

    .PARAMETER Body
        A string, a byte array, or an object to serialise as JSON. Nothing is sent when omitted.

    .PARAMETER ContentType
        The content type sent with a body. Defaults to JSON with the charset named.

    .PARAMETER JsonDepth
        How deep an object body is serialised.

    .OUTPUTS
        PSCustomObject with StatusCode, Headers and Content, the response text decoded as UTF-8,
        or an empty Content for a response with no body.

    .EXAMPLE
        PS> $response = Invoke-TestWebRequest -Uri $uri -Method GET -Headers @{ Authorization = "Bearer $token" }
        PS> $page = $response.Content | ConvertFrom-Json

        DESCRIPTION: One read, decoded correctly on both editions
        OUTPUT: The response text and headers
        USE CASE: Every Invoke-*Request in the module, and every token endpoint

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ContentType = 'application/json; charset=utf-8',

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$JsonDepth = 20
    )

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $arguments = @{
        Uri             = $Uri
        Method          = $Method
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }
    if ($Headers -and $Headers.Count -gt 0) { $arguments['Headers'] = $Headers }

    if ($null -ne $Body) {
        # Assigned inside each branch, not from the if as an expression: a statement's output is
        # enumerated on the way out, and a byte array assigned that way arrives as an array of
        # objects, which Invoke-WebRequest then sends as text.
        [byte[]]$bytes = $null
        if ($Body -is [byte[]]) {
            $bytes = $Body
        }
        elseif ($Body -is [string]) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        }
        else {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth $JsonDepth -Compress))
        }
        $arguments['Body'] = $bytes
        $arguments['ContentType'] = $ContentType
    }

    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Write-Verbose "$Method $Uri"
        $response = Invoke-WebRequest @arguments
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    $content = ''
    if ($response.RawContentStream -and $response.RawContentStream.Length -gt 0) {
        $content = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
    }
    elseif ($response.Content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
    }
    elseif ($null -ne $response.Content) {
        $content = [string]$response.Content
    }

    [PSCustomObject]@{
        StatusCode = $response.StatusCode
        Headers    = $response.Headers
        Content    = $content
    }
}
