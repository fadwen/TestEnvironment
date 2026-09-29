function Get-OneLoginAccessToken {
    <#
    .SYNOPSIS
        Returns a live OneLogin access token, renewing it when it is about to expire

    .DESCRIPTION
        OneLogin issues an API credential a bearer token through the OAuth 2 client credentials
        grant, at https://<subdomain>.onelogin.com/auth/oauth2/v2/token, authenticated with the
        client id and secret as HTTP Basic and a JSON body naming the grant. Verified live, the
        token lives ten hours and its scope comes back empty: what it may do is decided by the
        credential's scope in the admin portal, not by the token request.

        Ten hours is longer than any seed, but a connection held open across a working day
        outlives it, so the token is renewed here, a minute before expiry, and written back onto
        the connection. Invoke-OneLoginRequest also renews once on a 401, for a token revoked
        from the portal.

        The secret is held on the connection as a SecureString and converted for exactly as long
        as the request takes.

    .PARAMETER AsPlainText
        Return the bare token string rather than an object. Used by the request function, which
        needs it for an Authorization header.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        PSCustomObject describing the token, or System.String with -AsPlainText.

    .EXAMPLE
        PS> Get-TestAccessToken

        DESCRIPTION: Returns the current token's expiry and account
        OUTPUT: An object with ExpiresUtc and AccountId
        USE CASE: Checking that a connection is still good before a long run

    .EXAMPLE
        PS> $bearer = Get-OneLoginAccessToken -AsPlainText

        DESCRIPTION: Fetches the raw token for an Authorization header
        OUTPUT: The token string
        USE CASE: Called by Invoke-OneLoginRequest on every request

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

    if (-not $Connection) { $Connection = Get-OneLoginConnection }

    $needsToken = (
        [string]::IsNullOrWhiteSpace($Connection.AccessToken) -or
        -not $Connection.TokenExpiresUtc -or
        [DateTime]::UtcNow -ge $Connection.TokenExpiresUtc.AddSeconds(-60)
    )

    if ($needsToken) {
        Write-Verbose 'Requesting a OneLogin access token'
        $uri = 'https://{0}/auth/oauth2/v2/token' -f $Connection.ApiHost

        $basic = $null
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Connection.ClientSecret)
        try {
            $pair = '{0}:{1}' -f $Connection.ClientId, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
            $pair = $null
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        $requestedAt = [DateTime]::UtcNow
        try {
            $response = Invoke-TestWebRequest -Method POST -Uri $uri -Headers @{ Authorization = "Basic $basic" } `
                -Body @{ grant_type = 'client_credentials' }
            $payload = $response.Content | ConvertFrom-Json
        }
        catch {
            $detail = Get-OneLoginErrorDetail -ErrorRecord $_
            # Formatted as one string first: -f binds tighter than +, and a template built by
            # concatenation in the same expression goes out with its placeholders unfilled.
            $template = 'Could not get a OneLogin access token from {0}: {1}. A 401 here means the client id or secret is ' +
                'wrong, or the API credential was deleted in the admin portal.'
            throw ($template -f $uri, $detail.Summary)
        }
        finally {
            $basic = $null
        }

        $Connection.AccessToken = $payload.access_token
        $Connection.TokenExpiresUtc = $requestedAt.AddSeconds([int]$payload.expires_in)
        if ($payload.account_id) { $Connection.AccountId = [string]$payload.account_id }
    }

    if ($AsPlainText) { return $Connection.AccessToken }

    return [PSCustomObject]@{
        PSTypeName       = 'OneLoginAccessToken'
        Subdomain        = $Connection.Subdomain
        AccountId        = $Connection.AccountId
        ClientId         = $Connection.ClientId
        ExpiresUtc       = $Connection.TokenExpiresUtc
        ExpiresInSeconds = [int]([Math]::Max(0, ($Connection.TokenExpiresUtc - [DateTime]::UtcNow).TotalSeconds))
    }
}
