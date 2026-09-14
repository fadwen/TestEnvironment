function Export-AuthentikCredential {
    <#
    .SYNOPSIS
        Writes the service account credential record, with the token protected

    .DESCRIPTION
        The record names the instance, the account and where its token is. Writing it - the
        protected secret or the vault pointer, the UTF-8 bytes without a byte order mark, the
        folder and file restricted to the current user - is Export-TestCredentialRecord's job.
        This names the fields Authentik's record carries.

    .PARAMETER Path
        Where to write the record.

    .PARAMETER BaseUrl
        The instance the account belongs to.

    .PARAMETER Username
        The service account's username.

    .PARAMETER UserPk
        The service account's primary key.

    .PARAMETER Token
        The API token to store.

    .PARAMETER UseSecretStore
        Keep the token in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .OUTPUTS
        PSCustomObject with Path, Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Export-AuthentikCredential -Path $path -BaseUrl $url -Username $name -UserPk $pk -Token $token -Confirm:$false

        DESCRIPTION: Writes the record with the token DPAPI-protected
        OUTPUT: Path and Protection 'DPAPI'
        USE CASE: The end of New-AuthentikServiceApp

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Token',
        Justification = 'The token arrives from the API as a string and is protected before it touches disk.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [int]$UserPk,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'AuthentikEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the service account credential record')) {
        return $null
    }

    $record = [ordered]@{
        schemaVersion = 1
        baseUrl       = $BaseUrl
        username      = $Username
        userPk        = $UserPk
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    Export-TestCredentialRecord -Path $Path -Record $record -Secret $Token -SecretField 'tokenProtected' `
        -SecretName ('AuthentikEnvironment-{0}-{1}' -f ([uri]$BaseUrl).Host, $Username) `
        -UseSecretStore:$UseSecretStore -VaultName $VaultName -VaultPassword $VaultPassword -Confirm:$false
}
