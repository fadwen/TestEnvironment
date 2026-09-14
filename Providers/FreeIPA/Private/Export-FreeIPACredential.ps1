function Export-FreeIPACredential {
    <#
    .SYNOPSIS
        Writes the service account credential record, with the password protected

    .DESCRIPTION
        The record names the server, the account, the certificate authority the connection pinned,
        and where the password is. Writing it - the protected secret or the vault pointer, the UTF-8
        bytes without a byte order mark, the folder and file restricted to the current user - is
        Export-TestCredentialRecord's job. This names the fields FreeIPA's record carries.

        The CA certificate is kept in the record as PEM so that a later
        Connect-FreeIPAEnvironment -ServiceAccount trusts the same authority without being told
        again. It is a public certificate and needs no protection.

    .PARAMETER Path
        Where to write the record.

    .PARAMETER BaseUrl
        The server the account belongs to.

    .PARAMETER Username
        The service account's login.

    .PARAMETER Password
        The password to store.

    .PARAMETER CaCertificate
        The PEM of the pinned certificate authority, if any.

    .PARAMETER UseSecretStore
        Keep the password in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .OUTPUTS
        PSCustomObject with Path, Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Export-FreeIPACredential -Path $path -BaseUrl $url -Username $name -Password $password -Confirm:$false

        DESCRIPTION: Writes the record with the password DPAPI-protected
        OUTPUT: Path and Protection 'DPAPI'
        USE CASE: The end of New-FreeIPAServiceApp, and a rotation on connect

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password',
        Justification = 'The password is in memory as text from the API or a rotation and is protected before it touches disk.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
        Justification = 'The record stores exactly a login and its password; a PSCredential here would be unwrapped on the next line.')]
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
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter()]
        [string]$CaCertificate,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'FreeIPAEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the service account credential record')) {
        return $null
    }

    $record = [ordered]@{
        schemaVersion = 1
        provider      = 'FreeIPA'
        baseUrl       = $BaseUrl
        username      = $Username
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }
    if (-not [string]::IsNullOrWhiteSpace($CaCertificate)) { $record['caCertificate'] = $CaCertificate }

    Export-TestCredentialRecord -Path $Path -Record $record -Secret $Password -SecretField 'passwordProtected' `
        -SecretName ('FreeIPAEnvironment-{0}-{1}' -f ([uri]$BaseUrl).Host, $Username) `
        -UseSecretStore:$UseSecretStore -VaultName $VaultName -VaultPassword $VaultPassword -Confirm:$false
}
