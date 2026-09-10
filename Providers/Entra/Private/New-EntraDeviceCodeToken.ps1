function New-EntraDeviceCodeToken {
    <#
    .SYNOPSIS
        Signs a human in by device code and returns a delegated access token

    .DESCRIPTION
        This is the bootstrap credential, and it exists because Entra has no equivalent of
        Okta's SSWS token. There is nothing to paste: no long-lived personal API key a human
        can generate and hand to a script. The nearest thing is to sign the human in and act as
        them for exactly as long as it takes to create an application that can act on its own.

        Device code flow is used rather than an interactive browser redirect because it needs
        no listener, no reply URL and no registered application of its own. It prints a code,
        the human types it into a browser anywhere, and this polls until they finish. That
        works identically over SSH, in a container, and on a machine with no browser at all.

        The client is Microsoft Graph PowerShell's first-party application, which is
        pre-consented in every tenant. That is what makes the bootstrap possible without a
        chicken-and-egg problem: registering an application to register an application.

        The token this returns is DELEGATED - it carries the signed-in human's authority, not
        an application's. Everything it can do, they could do in the portal. It is deliberately
        short-lived and never written to disk: the certificate created during bootstrap is the
        durable credential, and this one exists only to create it.

    .PARAMETER TenantId
        Directory (tenant) ID, or a verified domain name

    .PARAMETER ClientId
        Public client to authenticate through. Defaults to Microsoft Graph PowerShell.

    .PARAMETER GraphBaseUri
        Graph endpoint the token is requested for

    .PARAMETER Scope
        The scopes to request. A bare name such as User.ReadWrite.All is taken as a Graph scope
        and prefixed with the endpoint; openid, profile and offline_access are sent as they are;
        '.default' asks for whatever the client has already been consented for. offline_access
        is always included, because without it there is no refresh token. Defaults to .default.

    .PARAMETER TimeoutSeconds
        How long to wait for the human before giving up

    .OUTPUTS
        System.Collections.Hashtable with AccessToken, RefreshToken and ExpiresOn.

    .EXAMPLE
        PS> New-EntraDeviceCodeToken -TenantId $tenant

        DESCRIPTION: Prints a code, waits for the human, returns their token
        OUTPUT: A hashtable carrying the access and refresh tokens
        USE CASE: Called by Connect-EntraEnvironment -Interactive

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The sign-in code is an instruction to a human standing at the console, not data. It must not be capturable into a variable, silenced by a caller who redirected the information stream, or lost from a transcript that shows only output - which is exactly what Write-Information, Write-Output and Write-Verbose would each do to it. This and the handover banner are the only Write-Host calls in the module.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Changes no state in the tenant. It obtains a token for the human already signing in, and the sign-in itself is the confirmation.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$GraphBaseUri = 'https://graph.microsoft.com',

        [Parameter()]
        [ValidateRange(60, 1800)]
        [int]$TimeoutSeconds = 900,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scope = @('.default')
    )

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        # offline_access is what earns a refresh token. Without it the bootstrap dies after an
        # hour, which is long enough to be intermittent rather than obviously broken.
        # Every Graph scope carries the resource as a prefix; the OpenID scopes do not. Asking
        # for named scopes rather than .default is what makes a first-party public client show
        # a consent screen for exactly the rights the module needs, so an interactive session
        # can do everything the service app can rather than only what the tenant happened to
        # have consented for it already.
        $openId = @('openid', 'profile', 'offline_access', 'email')
        $requested = foreach ($item in $Scope) {
            if ($openId -contains $item) { $item }
            elseif ($item -eq '.default' -or $item -like 'https://*') { if ($item -eq '.default') { "$GraphBaseUri/.default" } else { $item } }
            else { "$GraphBaseUri/$item" }
        }
        if ($requested -notcontains 'offline_access') { $requested = @($requested) + 'offline_access' }
        $scope = ($requested -join ' ')
        $body = 'client_id={0}&scope={1}' -f [uri]::EscapeDataString($ClientId), [uri]::EscapeDataString($scope)

        try {
            $response = Invoke-WebRequest -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
                -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop
            $device = ([System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())) | ConvertFrom-Json
        }
        catch {
            throw (New-Object System.Exception(
                "Could not start device code sign-in: $(Get-EntraErrorDetail -ErrorRecord $_)", $_.Exception))
        }

        # Write-Host is the right call here and the only place in the module that uses it.
        # This is an instruction to a human standing at the console, not data: it must not be
        # capturable into a variable, redirected into a transcript as output, or silenced by a
        # caller who suppressed the information stream.
        Write-Host ''
        Write-Host '  Sign in to authorise the bootstrap:' -ForegroundColor Cyan
        Write-Host "    1. Open $($device.verification_uri)"
        Write-Host "    2. Enter the code: $($device.user_code)" -ForegroundColor Yellow
        Write-Host '    3. Sign in as a Global Administrator of this tenant'
        Write-Host ''
        Write-Host '  Waiting...' -ForegroundColor DarkGray

        $deadline = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Min($TimeoutSeconds, [int]$device.expires_in))
        $interval = [Math]::Max(5, [int]$device.interval)

        $pollBody = 'grant_type={0}&client_id={1}&device_code={2}' -f
            [uri]::EscapeDataString('urn:ietf:params:oauth:grant-type:device_code'),
            [uri]::EscapeDataString($ClientId),
            [uri]::EscapeDataString($device.device_code)

        while ([DateTimeOffset]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds $interval

            try {
                $tokenResponse = Invoke-WebRequest -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                    -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes($pollBody)) `
                    -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop

                $token = ([System.Text.Encoding]::UTF8.GetString($tokenResponse.RawContentStream.ToArray())) | ConvertFrom-Json

                Write-Host '  Signed in.' -ForegroundColor Green
                return @{
                    AccessToken  = $token.access_token
                    RefreshToken = $token.refresh_token
                    ExpiresOn    = [DateTimeOffset]::UtcNow.AddSeconds([int]$token.expires_in)
                    ClientId     = $ClientId
                }
            }
            catch {
                # authorization_pending is the normal state for as long as the human is still
                # typing, so it is not an error. Everything else is.
                $detail = Get-EntraErrorDetail -ErrorRecord $_
                if ($detail -match 'authorization_pending|AADSTS70016') { continue }
                if ($detail -match 'slow_down') { $interval += 5; continue }
                if ($detail -match 'authorization_declined') {
                    Write-Error 'Sign-in was declined.' -ErrorAction Stop
                    return
                }
                if ($detail -match 'expired_token|code_expired') {
                    Write-Error 'The device code expired before sign-in completed.' -ErrorAction Stop
                    return
                }
                throw (New-Object System.Exception("Device code sign-in failed: $detail", $_.Exception))
            }
        }

        Write-Error "Timed out after $TimeoutSeconds seconds waiting for sign-in." -ErrorAction Stop
    }
    finally {
        $ProgressPreference = $previousProgress
    }
}
