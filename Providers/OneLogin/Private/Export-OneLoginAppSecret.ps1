function Export-OneLoginAppSecret {
    <#
    .SYNOPSIS
        Saves a seeded app's client id and secret, with the secret protected

    .DESCRIPTION
        OneLogin shows an app's client secret once, in the answer to its creation; a later read of
        the app returns the client id and no secret. New-OneLoginApp -SaveAppSecret hands that
        answer here, and nowhere else, so the secret can be used later to test a sign-in against
        the seeded app.

        Writing the record - the protected secret or the vault pointer, the UTF-8 bytes without a
        byte order mark, the folder and file restricted to the current user - is
        Export-TestCredentialRecord's job, the same writer the account's own API credential goes
        through. This names the fields an app record carries: the account, the app's id, key and
        name, and its client id.

        Remove-OneLoginEnvironment deletes the record, and the vault secret it points to, when it
        deletes the app, so saved secrets do not outlive the apps they open.

    .PARAMETER Subdomain
        The account the app lives in.

    .PARAMETER AppId
        The app's id in OneLogin.

    .PARAMETER AppKey
        The app's key in the seed data.

    .PARAMETER AppName
        The app's name, with the prefix.

    .PARAMETER ClientId
        The app's client id.

    .PARAMETER ClientSecret
        The app's client secret.

    .PARAMETER UseSecretStore
        Keep the secret in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .OUTPUTS
        PSCustomObject with Path, Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Export-OneLoginAppSecret -Subdomain contoso -AppId 42 -AppKey expenses -AppName 'ZZ-TEST-Expenses Web' -ClientId $id -ClientSecret $secret -Confirm:$false

        DESCRIPTION: Saves the app's secret DPAPI-protected
        OUTPUT: Path and Protection 'DPAPI'
        USE CASE: New-OneLoginApp -SaveAppSecret, as each app is created

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'ClientSecret',
        Justification = 'The secret arrives as text in the API response and is protected before it touches disk.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subdomain,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+$')]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientSecret,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'OneLoginEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    $path = Get-OneLoginAppSecretPath -Subdomain $Subdomain -AppId $AppId
    if (-not $PSCmdlet.ShouldProcess($path, "Save the client secret of OneLogin app $AppName")) {
        return $null
    }

    $record = [ordered]@{
        schemaVersion = 1
        subdomain     = $Subdomain.ToLowerInvariant()
        appId         = $AppId
        appKey        = $AppKey
        appName       = $AppName
        clientId      = $ClientId
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    Export-TestCredentialRecord -Path $path -Record $record -Secret $ClientSecret -SecretField 'clientSecretProtected' `
        -SecretName ('OneLoginEnvironment-{0}-app-{1}' -f $Subdomain.ToLowerInvariant(), $AppId) `
        -UseSecretStore:$UseSecretStore -VaultName $VaultName -VaultPassword $VaultPassword -Confirm:$false
}
