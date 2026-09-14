function Export-OktaAppCredential {
    <#
    .SYNOPSIS
        Writes the service app's client id and private key to protected storage

    .DESCRIPTION
        This is the handover point between the two authentication modes: everything before it
        runs on the SSWS token you pasted in, everything after it can run on the app. The record
        names the org, the app and its scopes, and where the private key is. Writing it - the
        protected key or the vault pointer, the UTF-8 bytes without a byte order mark, the folder
        and file restricted to the current user - is Export-TestCredentialRecord's job. This names
        the fields Okta's record carries; the key travels as its JWK serialised to JSON.

    .PARAMETER Path
        Destination file.

    .PARAMETER OrgUrl
        Org the credential belongs to.

    .PARAMETER ClientId
        The service app client_id.

    .PARAMETER AppId
        The application id, which is what the app is deleted by.

    .PARAMETER Label
        The app's label, for the credential report.

    .PARAMETER Scopes
        The scopes granted to the app.

    .PARAMETER PrivateJwk
        The private key as a JWK.

    .PARAMETER UseSecretStore
        Store the key in a SecretStore vault instead of encrypting it into the file.

    .PARAMETER VaultName
        Vault to use when -UseSecretStore is specified.

    .PARAMETER VaultPassword
        Password for the vault when -UseSecretStore is specified.

    .OUTPUTS
        PSCustomObject describing what was written.

    .EXAMPLE
        PS> Export-OktaAppCredential -Path $path -OrgUrl $org -ClientId $id -AppId $appId -Label 'OKTALAB Automation' -Scopes $scopes -PrivateJwk $jwk

        DESCRIPTION: Writes the record with the key DPAPI-protected
        OUTPUT: Path, ClientId, AppId, Scopes and Protection
        USE CASE: The end of New-OktaServiceApp

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OrgUrl,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AppId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Scopes,
        [Parameter(Mandatory = $true)][object]$PrivateJwk,
        [Parameter()][switch]$UseSecretStore,
        [Parameter()][string]$VaultName = 'OktaEnvironment',
        [Parameter()][System.Security.SecureString]$VaultPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the service app credential')) {
        return $null
    }

    $record = [ordered]@{
        schemaVersion = 2
        orgUrl        = $OrgUrl.TrimEnd('/')
        clientId      = $ClientId
        appId         = $AppId
        label         = $Label
        scopes        = @($Scopes)
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    $written = Export-TestCredentialRecord -Path $Path -Record $record `
        -Secret ($PrivateJwk | ConvertTo-Json -Depth 10 -Compress) -SecretField 'privateJwkProtected' `
        -SecretName ('OktaEnvironment-{0}-{1}' -f ([uri]$OrgUrl).Host, $ClientId) `
        -UseSecretStore:$UseSecretStore -VaultName $VaultName -VaultPassword $VaultPassword -Confirm:$false

    return [PSCustomObject]@{
        Path          = $Path
        ClientId      = $ClientId
        AppId         = $AppId
        Scopes        = @($Scopes)
        Protection    = $written.Protection
        VaultName     = $written.VaultName
        SecretName    = $written.SecretName
        FileProtected = $true
    }
}
