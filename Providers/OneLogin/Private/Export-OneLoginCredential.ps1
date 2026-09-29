function Export-OneLoginCredential {
    <#
    .SYNOPSIS
        Writes an account's API credential record, with the client secret protected

    .DESCRIPTION
        The record names the account and the credential's client id, and holds the secret.
        Writing it - the protected secret or the vault pointer, the UTF-8 bytes without a byte
        order mark, the folder and file restricted to the current user - is
        Export-TestCredentialRecord's job. This names the fields OneLogin's record carries.

        The client id is kept in the record rather than asked for again, because -UseStoredSecret
        should need nothing but the subdomain. It is not secret: it identifies the credential and
        grants nothing without the secret beside it.

    .PARAMETER Path
        Where to write the record.

    .PARAMETER Subdomain
        The account the credential belongs to.

    .PARAMETER ClientId
        The API credential's client id.

    .PARAMETER ClientSecret
        The API credential's client secret.

    .PARAMETER UseSecretStore
        Keep the secret in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .OUTPUTS
        PSCustomObject with Path, Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Export-OneLoginCredential -Path $path -Subdomain contoso -ClientId $id -ClientSecret $secret -Confirm:$false

        DESCRIPTION: Writes the record with the secret DPAPI-protected
        OUTPUT: Path and Protection 'DPAPI'
        USE CASE: Connect-OneLoginEnvironment -SaveSecret, once the connection is proved

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'ClientSecret',
        Justification = 'The secret is materialised for the length of this call and protected before it touches disk.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subdomain,

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

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the OneLogin credential record')) {
        return $null
    }

    $record = [ordered]@{
        schemaVersion = 1
        subdomain     = $Subdomain
        clientId      = $ClientId
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    Export-TestCredentialRecord -Path $Path -Record $record -Secret $ClientSecret -SecretField 'clientSecretProtected' `
        -SecretName ('OneLoginEnvironment-{0}' -f $Subdomain) `
        -UseSecretStore:$UseSecretStore -VaultName $VaultName -VaultPassword $VaultPassword -Confirm:$false
}
