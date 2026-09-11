function Export-FreeIPACredential {
    <#
    .SYNOPSIS
        Writes the service account credential record, with the password protected

    .DESCRIPTION
        The record names the server, the account, the certificate authority the connection
        pinned, and where the password is. The password itself goes to one of two places, and
        the record is the authority on which: into a SecretStore vault under -UseSecretStore,
        which is encrypted and portable, or into the record DPAPI-protected, which is
        encrypted on Windows only. A record written before the vault was proven usable would
        name a secret that was never stored, so the vault is initialised first and the record
        last.

        The CA certificate is kept in the record as PEM so that a later
        Connect-FreeIPAEnvironment -ServiceAccount trusts the same authority without being
        told again. It is a public certificate and needs no protection.

        Written as UTF-8 bytes rather than through Set-Content, which on Windows PowerShell
        prepends a byte order mark that a strict JSON reader rejects. The folder is restricted
        to the current user before the file exists in it, and the file again afterwards.

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
        Justification = 'The password is in memory as text from the API or a rotation and is protected here before it touches disk.')]
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

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
        $null = Protect-TestFile -Path $folder -Confirm:$false
    }

    $payload = [ordered]@{
        schemaVersion = 1
        provider      = 'FreeIPA'
        baseUrl       = $BaseUrl
        username      = $Username
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }
    if (-not [string]::IsNullOrWhiteSpace($CaCertificate)) { $payload['caCertificate'] = $CaCertificate }

    $secretName = $null
    if ($UseSecretStore) {
        $secretName = 'FreeIPAEnvironment-{0}-{1}' -f ([uri]$BaseUrl).Host, $Username
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install
        if (-not $vault -or -not $vault.Available) {
            throw "Vault '$VaultName' is not usable, so the password was not stored."
        }
        Set-TestVaultSecret -VaultName $VaultName -SecretName $secretName -PlainText $Password
        $payload['protection'] = 'SecretStore'
        $payload['vaultName'] = $VaultName
        $payload['secretName'] = $secretName
    }
    else {
        $protected = Protect-TestSecret -PlainText $Password
        $payload['protection'] = $protected.Method
        $payload['passwordProtected'] = $protected.Value
    }

    $json = $payload | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::UTF8.GetBytes($json))
    $null = Protect-TestFile -Path $Path -Confirm:$false

    return [PSCustomObject]@{
        Path       = $Path
        Protection = $payload['protection']
        VaultName  = $(if ($UseSecretStore) { $VaultName } else { $null })
        SecretName = $secretName
    }
}
