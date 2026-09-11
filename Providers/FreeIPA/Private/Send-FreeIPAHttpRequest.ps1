function Send-FreeIPAHttpRequest {
    <#
    .SYNOPSIS
        Sends one HTTP request through a connection's client and returns status, headers and body

    .DESCRIPTION
        The only function that touches the network for the FreeIPA provider, which is what the
        tests mock. It sends a form or a JSON body to a path under the server, reads the
        response as UTF-8 bytes rather than trusting an inferred charset - the seed carries
        accented names on purpose - and returns the pieces the callers switch on: the status
        code, the headers FreeIPA answers with (a login failure is explained in
        X-IPA-Rejection-Reason, a password change in X-IPA-Pwchange-Result) and the body.

        Nothing is thrown for a non-success status. A 401 is a normal answer that
        Invoke-FreeIPARequest turns into a new login, so the decision belongs to the caller.

    .PARAMETER Connection
        The connection whose client to send through.

    .PARAMETER Path
        The path under the server, for example '/ipa/session/json'.

    .PARAMETER Form
        Form fields, sent URL-encoded.

    .PARAMETER Json
        A JSON document, sent as application/json.

    .PARAMETER Accept
        The Accept header. FreeIPA's login endpoints want text/plain; the API wants JSON.

    .OUTPUTS
        PSCustomObject with StatusCode, Headers and Body.

    .EXAMPLE
        PS> Send-FreeIPAHttpRequest -Connection $connection -Path '/ipa/session/json' -Json $payload -Accept 'application/json'

        DESCRIPTION: Sends a JSON-RPC call
        OUTPUT: The status, headers and raw body
        USE CASE: Invoke-FreeIPARequest

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(DefaultParameterSetName = 'Json')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Connection,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Form')]
        [hashtable]$Form,

        [Parameter(Mandatory = $true, ParameterSetName = 'Json')]
        [string]$Json,

        [Parameter()]
        [string]$Accept = 'application/json'
    )

    $client = $Connection.Client
    if (-not $client) { throw 'The connection holds no HTTP client. Reconnect with Connect-TestEnvironment.' }

    $uri = '{0}{1}' -f $Connection.BaseUrl.TrimEnd('/'), $Path
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $uri)
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Form') {
            $fields = [System.Collections.Generic.Dictionary[string, string]]::new()
            foreach ($key in $Form.Keys) { $fields[[string]$key] = [string]$Form[$key] }
            $request.Content = [System.Net.Http.FormUrlEncodedContent]::new($fields)
        }
        else {
            $request.Content = [System.Net.Http.StringContent]::new($Json, [System.Text.Encoding]::UTF8, 'application/json')
        }
        $request.Headers.Accept.ParseAdd($Accept)

        Write-Verbose "FreeIPA POST $Path"
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $body = ''
            if ($bytes -and $bytes.Length -gt 0) { $body = [System.Text.Encoding]::UTF8.GetString($bytes) }

            $headers = @{}
            foreach ($header in $response.Headers) { $headers[[string]$header.Key] = (@($header.Value) -join ', ') }

            return [PSCustomObject]@{
                StatusCode = [int]$response.StatusCode
                Headers    = $headers
                Body       = $body
            }
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $request.Dispose()
    }
}
