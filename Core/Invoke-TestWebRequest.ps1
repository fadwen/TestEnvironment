function Invoke-TestWebRequest {
    <#
    .SYNOPSIS
        The one HTTP call every REST provider makes, done the way this PowerShell does it best

    .DESCRIPTION
        Every request the module sends to Entra, Okta, Authentik or PingOne, and every token
        request, goes through here. Windows PowerShell 5.1 corrupts non-ASCII text in both
        directions, silently, and hides the body of a failed response on a stream; PowerShell 7
        gets the text right and can hand a failed response back like any other. Rather than test
        the edition in every request function, this reads Get-TestRuntime once and does each
        thing the way the running PowerShell supports:

        - The body goes out as UTF-8 bytes with the charset named, on both editions. A string
          body is sent by 5.1 as ISO-8859-1 when no charset is named, whatever the machine's code
          page: observed against PingOne, an accented e went out as the lone byte E9 and was
          stored as U+FFFD, and a Han character as '?'. A string is encoded, an object is
          serialised to JSON and encoded, and a byte array is sent as it stands.
        - The response is decoded from its raw bytes as UTF-8, never from .Content, on both. 5.1
          decodes by the declared charset and falls back to Latin-1, and Okta declares none.
        - A failed response is read the way this PowerShell allows. With -SkipHttpErrorCheck
          (PowerShell 7) a 4xx or 5xx comes back as a response and its body is decoded like any
          other; without it (Windows PowerShell) the cmdlet throws and the body is read from the
          exception's response stream, once. Either way the caller receives the one error shape
          New-TestWebRequestError describes: the status as an integer, the headers as a
          case-insensitive hashtable, the body in ErrorDetails. A transport failure with no
          response propagates untouched.
        - TLS 1.2 is added on Windows PowerShell, which can still default to TLS 1.0, only ever
          adding to the enabled set. PowerShell 7 negotiates on its own.
        - The progress bar is suppressed around the call, which on 5.1 costs more than the call,
          and the preference is restored whether the call threw or not.

        Get-TestRuntime detects each of those on the cmdlet itself, not from a version number.

    .PARAMETER Uri
        The absolute URI.

    .PARAMETER Method
        GET, POST, PUT, PATCH or DELETE.

    .PARAMETER Headers
        Request headers, authorization included. Content-Type is set from -ContentType.

    .PARAMETER Body
        A string, a byte array, or an object to serialise as JSON. Nothing is sent when omitted.

    .PARAMETER ContentType
        The content type sent with a body. Defaults to JSON with the charset named.

    .PARAMETER JsonDepth
        How deep an object body is serialised. ConvertTo-Json's default of two silently
        flattens anything nested further.

    .EXAMPLE
        PS> $response = Invoke-TestWebRequest -Uri 'https://api.example.com/users' -Method POST -Headers $auth -Body @{ name = 'José' }
        PS> $page = $response.Content | ConvertFrom-Json

        DESCRIPTION: Sends one JSON body and reads the answer
        OUTPUT: StatusCode, Headers and the decoded Content
        USE CASE: Called by every provider's Invoke-<Provider>Request

    .EXAMPLE
        PS> try { Invoke-TestWebRequest -Uri $uri -Method GET -Headers $auth } catch { $_.Exception.Response.StatusCode; $_.ErrorDetails.Message }

        DESCRIPTION: Reads a failure the same way on either edition
        OUTPUT: The status and the body the server sent
        USE CASE: Every provider's retry and error handling

    .OUTPUTS
        PSCustomObject with StatusCode (integer), Headers (case-insensitive hashtable, each
        value a string) and Content (the body as a string, empty when there was none).

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

    $runtime = Get-TestRuntime

    if (-not $runtime.Capability.ModernTls) {
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
    if ($runtime.Capability.SkipHttpErrorCheck) { $arguments['SkipHttpErrorCheck'] = $true }
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

    # Every header value as one string under a case-insensitive key - a PowerShell hashtable
    # literal keys that way - whichever collection the response carried: a hashtable, a
    # WebHeaderCollection, PowerShell 7's dictionary of string arrays, or an HttpResponseMessage's
    # enumerable of pairs. Multiple values are joined the way the wire joins them, so a
    # provider's Link parsing reads one string on both editions.
    $toHeaderTable = {
        param($source)
        $table = @{}
        if ($null -eq $source) { return $table }
        if ($source -is [System.Collections.IDictionary]) {
            foreach ($key in @($source.Keys)) { $table[[string]$key] = (@($source[$key]) -join ', ') }
        }
        elseif ($source -is [System.Collections.Specialized.NameValueCollection]) {
            foreach ($key in @($source.AllKeys)) { if ($null -ne $key) { $table[[string]$key] = [string]$source[$key] } }
        }
        elseif ($source -is [System.Collections.IEnumerable]) {
            foreach ($pair in $source) {
                if ($null -ne $pair -and $pair.PSObject.Properties['Key']) { $table[[string]$pair.Key] = (@($pair.Value) -join ', ') }
            }
        }
        return $table
    }
    $decode = {
        param($response)
        if ($response.RawContentStream -and $response.RawContentStream.Length -gt 0) {
            return [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
        }
        if ($response.Content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($response.Content) }
        if ($null -ne $response.Content) { return [string]$response.Content }
        return ''
    }

    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $failure = $null
    try {
        Write-Verbose "$Method $Uri"
        $response = Invoke-WebRequest @arguments
    }
    catch {
        # Windows PowerShell's way: the cmdlet threw, and the status, headers and body are on the
        # exception's response. The stream can be read once, so this is the only place that reads
        # it. A record that already carries the body in ErrorDetails - which is what a test's
        # fake, or PowerShell 7 without the switch, hands over - is read from there instead. An
        # exception with no response at all is a transport failure and is not this function's
        # to describe.
        $thrown = $_
        $errorResponse = $null
        if ($thrown.Exception.PSObject.Properties['Response'] -and $thrown.Exception.Response) { $errorResponse = $thrown.Exception.Response }
        if ($null -eq $errorResponse) { throw }

        $status = 0
        try { $status = [int]$errorResponse.StatusCode } catch { $status = 0 }
        if ($status -le 0) { throw }

        $body = $null
        if ($thrown.ErrorDetails -and -not [string]::IsNullOrEmpty($thrown.ErrorDetails.Message)) {
            $body = $thrown.ErrorDetails.Message
        }
        elseif ($errorResponse.PSObject.Methods['GetResponseStream']) {
            try {
                $stream = $errorResponse.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
                }
            }
            catch { Write-Verbose "Could not read the failed response's body: $($_.Exception.Message)" }
        }
        $description = if ($errorResponse.PSObject.Properties['StatusDescription']) { [string]$errorResponse.StatusDescription }
        elseif ($errorResponse.PSObject.Properties['ReasonPhrase']) { [string]$errorResponse.ReasonPhrase } else { '' }
        # Assigned inside the if, not from it as an expression: a statement's output is
        # enumerated on the way out, and a WebHeaderCollection assigned that way arrives as an
        # array of its key names, with every value gone.
        $headerSource = $null
        if ($errorResponse.PSObject.Properties['Headers']) { $headerSource = $errorResponse.Headers }
        $failure = New-TestWebRequestError -Method $Method -Uri $Uri -StatusCode $status -StatusDescription $description `
            -Headers (& $toHeaderTable $headerSource) -Body $body -InnerException $thrown.Exception
    }
    finally {
        $ProgressPreference = $previousProgress
    }
    if ($failure) { $PSCmdlet.ThrowTerminatingError($failure) }

    $content = & $decode $response
    $headerTable = & $toHeaderTable $response.Headers
    $statusCode = [int]$response.StatusCode

    # PowerShell 7's way: with -SkipHttpErrorCheck a failed response arrives here like any other,
    # body already decoded from its raw bytes, and becomes the same record the catch above builds.
    if ($statusCode -ge 400) {
        $description = if ($response.PSObject.Properties['StatusDescription']) { [string]$response.StatusDescription } else { '' }
        $failure = New-TestWebRequestError -Method $Method -Uri $Uri -StatusCode $statusCode -StatusDescription $description `
            -Headers $headerTable -Body $content
        $PSCmdlet.ThrowTerminatingError($failure)
    }

    [PSCustomObject]@{
        StatusCode = $statusCode
        Headers    = $headerTable
        Content    = $content
    }
}
