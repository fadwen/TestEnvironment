function Get-PingOneAccessToken {
    <#
    .SYNOPSIS
        Returns a live PingOne access token, renewing it when it is about to expire

    .DESCRIPTION
        PingOne issues a worker application an access token that lives an hour. That is longer
        than most steps and shorter than a seed of any size, so a token fetched at connect time
        and never looked at again produces a 401 partway through a run - typically during
        teardown, which is the worst moment for a run to stop.

        The token is therefore renewed here rather than by any caller, a minute before it
        expires, and the renewed value is written back onto the connection so the next call
        finds it already fresh.

        The token endpoint belongs to the environment the worker application LIVES in, which is
        not necessarily the environment being seeded. Posting to the target environment's
        endpoint with a worker from elsewhere is refused with `invalid_client`, a message that
        reads like a disabled application or a bad secret and is neither. That is why the
        connection carries AuthEnvironmentId separately, and why this function uses it.

        The secret is held on the connection as a SecureString and converted for exactly as
        long as the request takes.

    .PARAMETER AsPlainText
        Return the bare token string rather than an object. Used by the request function, which
        needs it for an Authorization header.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        PSCustomObject describing the token, or System.String with -AsPlainText.

    .EXAMPLE
        PS> Get-TestAccessToken

        DESCRIPTION: Returns the current token and when it expires
        OUTPUT: An object with ExpiresUtc and the scopes the token carries
        USE CASE: Checking that a connection is still good before a long run

    .EXAMPLE
        PS> $bearer = Get-PingOneAccessToken -AsPlainText

        DESCRIPTION: Fetches the raw token for an Authorization header
        OUTPUT: The token string
        USE CASE: Called by Invoke-PingOneRequest on every request

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AsPlainText,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-PingOneConnection }

    $needsToken = (
        [string]::IsNullOrWhiteSpace($Connection.AccessToken) -or
        -not $Connection.TokenExpiresUtc -or
        [DateTime]::UtcNow -ge $Connection.TokenExpiresUtc.AddSeconds(-60)
    )

    if ($needsToken) {
        Write-Verbose 'Requesting a PingOne access token'

        # Windows PowerShell can default to TLS 1.0, which PingOne refuses. Reachable directly
        # through Get-TestAccessToken, so it cannot rely on the request function having set it.
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $tls12 = [System.Net.SecurityProtocolType]::Tls12
            if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
                [System.Net.ServicePointManager]::SecurityProtocol =
                    [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
            }
        }

        $uri = 'https://{0}/{1}/as/token' -f $Connection.AuthHost, $Connection.AuthEnvironmentId

        # Basic, because that is what a worker application is created with. The secret is
        # materialised here and nowhere else, and only for the length of the call.
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Connection.ClientSecret)
        try {
            $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $pair = '{0}:{1}' -f $Connection.ClientId, $secret
            $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        $requestedAt = [DateTime]::UtcNow

        # Encoded as the HTTP encoding invariant in CLAUDE.md requires: the form body sent as UTF-8
        # bytes, the response decoded from its raw bytes as UTF-8, and no progress bar. The payload is plain
        # ASCII today, so this is consistency with the request function rather than a fix, and it
        # keeps a second decoding path from quietly relying on a declared charset.
        $previousProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            $response = Invoke-WebRequest -Method POST -Uri $uri -UseBasicParsing -ErrorAction Stop `
                -Headers @{ Authorization = "Basic $basic" } `
                -Body ([System.Text.Encoding]::UTF8.GetBytes('grant_type=client_credentials')) `
                -ContentType 'application/x-www-form-urlencoded'
            $payload = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()) | ConvertFrom-Json
        }
        catch {
            $detail = Get-PingOneErrorDetail -ErrorRecord $_
            # Formatted as one string first. Written as 'a {0}' + 'b' + 'c' -f ..., the -f binds
            # to the last literal only, because it binds tighter than +, and the message went out
            # with its placeholders unfilled.
            $template = 'Could not get a PingOne access token from {0}: {1}. An invalid_client here ' +
                'usually means the worker application lives in a different environment from the ' +
                'one named by -AuthEnvironmentId, or that it is disabled.'
            throw ($template -f $uri, $detail.Summary)
        }
        finally {
            $ProgressPreference = $previousProgress
            $basic = $null
            $pair = $null
            $secret = $null
        }

        $Connection.AccessToken = $payload.access_token
        $Connection.TokenExpiresUtc = $requestedAt.AddSeconds([int]$payload.expires_in)
        $Connection.TokenScopes = @(($payload.scope -split '\s+') | Where-Object { $_ })
    }

    if ($AsPlainText) { return $Connection.AccessToken }

    return [PSCustomObject]@{
        PSTypeName       = 'PingOneAccessToken'
        EnvironmentId    = $Connection.EnvironmentId
        AuthEnvironmentId = $Connection.AuthEnvironmentId
        ClientId         = $Connection.ClientId
        ExpiresUtc       = $Connection.TokenExpiresUtc
        ExpiresInSeconds = [int]([Math]::Max(0, ($Connection.TokenExpiresUtc - [DateTime]::UtcNow).TotalSeconds))
        Scopes           = $Connection.TokenScopes
    }
}
