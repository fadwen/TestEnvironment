function Get-EntraAccessToken {
    <#
    .SYNOPSIS
        Exchanges a signed client assertion for a Graph access token

    .DESCRIPTION
        Performs the client credentials grant against the tenant's v2.0 token endpoint,
        authenticating with a certificate rather than a secret.

        The token is cached on the connection and reused until it is within two minutes of
        expiry, then silently renewed. Two minutes rather than nothing because a token that
        passes the expiry check and then expires in flight produces a 401 on an arbitrary
        call in the middle of a seed run, which is a confusing way to discover a clock is
        slightly off.

        App-only tokens carry no refresh token by design, so renewal means signing a fresh
        assertion. That costs one local RSA signature, which is why there is no attempt to
        persist tokens between sessions - it would trade a millisecond of CPU for a bearer
        token sitting on disk.

    .PARAMETER Force
        Requests a new token even if the cached one is still valid

    .PARAMETER AsPlainText
        Returns the raw token string instead of the summary object. Intended for handing a
        bearer token to another tool; be aware it will appear in a transcript.

    .PARAMETER Connection
        Connection to use instead of the module's active one. Connect-EntraEnvironment
        passes this to validate a credential before storing it.

    .OUTPUTS
        EntraAccessToken, or System.String with -AsPlainText

    .EXAMPLE
        PS> Get-EntraAccessToken

        DESCRIPTION: Returns the cached token's metadata, renewing it if it is close to expiry
        OUTPUT: An object with ExpiresOn, ExpiresInMinutes and the granted roles
        USE CASE: Checking what the app is actually authorised to do before a seed run

    .EXAMPLE
        PS> $bearer = Get-EntraAccessToken -AsPlainText

        DESCRIPTION: Retrieves the raw token
        OUTPUT: eyJ0eXAiOiJKV1QiLCJub25jZSI6...
        USE CASE: Calling Graph from curl, or from a tool that takes a bearer token directly

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraAccessToken')]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$AsPlainText,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }

    $needsToken = $Force -or
        [string]::IsNullOrWhiteSpace($Connection.AccessToken) -or
        ($null -eq $Connection.TokenExpiresOn) -or
        ([DateTimeOffset]::UtcNow.AddMinutes(2) -ge $Connection.TokenExpiresOn)

    if ($needsToken) {
        $tokenUri = "https://login.microsoftonline.com/$($Connection.TenantId)/oauth2/v2.0/token"

        # Form encoding, not JSON. The token endpoint is OAuth 2.0 rather than Graph, and it
        # answers a JSON body with an unhelpful 400 rather than an error naming the format.
        $form = if ($Connection.AuthMode -eq 'DeviceCode') {
            # A delegated session, renewed with the refresh token the device code flow
            # returned. There is no certificate to sign with here, and no way to obtain a new
            # token without the human, so an expired refresh token has to fail loudly rather
            # than silently degrade.
            if (-not $Connection.RefreshToken) {
                Write-Error ("The interactive session has expired and there is no refresh token to renew it. " +
                    "Run Connect-TestEnvironment -Provider Entra -Interactive again.") -ErrorAction Stop
                return
            }
            @{
                client_id     = $Connection.ClientId
                scope         = "$($Connection.GraphBaseUri)/.default offline_access"
                grant_type    = 'refresh_token'
                refresh_token = $Connection.RefreshToken
            }
        }
        else {
            $assertion = New-EntraClientAssertion -Certificate $Connection.Certificate `
                -ClientId $Connection.ClientId -TenantId $Connection.TenantId
            @{
                client_id             = $Connection.ClientId
                scope                 = "$($Connection.GraphBaseUri)/.default"
                grant_type            = 'client_credentials'
                client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                client_assertion      = $assertion
            }
        }
        $body = ($form.GetEnumerator() | ForEach-Object {
            '{0}={1}' -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value)
        }) -join '&'

        $previousProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Write-Verbose "Requesting an access token from $tokenUri"
            $response = Invoke-WebRequest -Uri $tokenUri -Method POST `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                -ContentType 'application/x-www-form-urlencoded' `
                -UseBasicParsing -ErrorAction Stop

            $payload = ([System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())) | ConvertFrom-Json
        }
        catch {
            # Entra puts the actionable part in error_description, including the AADSTS code,
            # and PowerShell discards the response body by default on both editions.
            $detail = Get-EntraErrorDetail -ErrorRecord $_
            throw (New-Object System.Exception("Token request failed for client $($Connection.ClientId): $detail", $_.Exception))
        }
        finally {
            $ProgressPreference = $previousProgress
        }

        $Connection.AccessToken = $payload.access_token
        $Connection.TokenExpiresOn = [DateTimeOffset]::UtcNow.AddSeconds([int]$payload.expires_in)
        $Connection.TokenRoles = @(Get-EntraTokenRole -AccessToken $payload.access_token)

        # Entra rotates the refresh token on every use, so the old one stops working the
        # moment this succeeds. Keeping the previous value would make the session survive
        # exactly one renewal.
        if ($payload.PSObject.Properties['refresh_token'] -and $payload.refresh_token) {
            $Connection.RefreshToken = $payload.refresh_token
        }
        Write-Verbose "Token acquired, valid until $($Connection.TokenExpiresOn.ToLocalTime())"
    }

    if ($AsPlainText) { return $Connection.AccessToken }

    return [PSCustomObject]@{
        PSTypeName       = 'EntraAccessToken'
        TenantId         = $Connection.TenantId
        ClientId         = $Connection.ClientId
        ExpiresOn        = $Connection.TokenExpiresOn.ToLocalTime()
        ExpiresInMinutes = [Math]::Round(($Connection.TokenExpiresOn - [DateTimeOffset]::UtcNow).TotalMinutes, 1)
        Roles            = $Connection.TokenRoles
    }
}
