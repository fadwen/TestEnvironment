function Export-AuthentikCredential {
    <#
    .SYNOPSIS
        Writes the service account credential record, with the token protected

    .DESCRIPTION
        The record names the instance, the account and where its token is. The token itself
        goes to one of two places, and the record is the authority on which: into a
        SecretStore vault under -UseSecretStore, which is encrypted and portable, or into the
        record DPAPI-protected, which is encrypted on Windows only. A record written before
        the vault was proven usable would name a secret that was never stored, so the vault is
        initialised first and the record last.

        Written as UTF-8 bytes rather than through Set-Content, which on Windows PowerShell
        prepends a byte order mark that a strict JSON reader rejects. The folder is restricted
        to the current user before the file exists in it, and the file again afterwards.

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
        Justification = 'The token arrives from the API as a string and is protected here before it touches disk.')]
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

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
        $null = Protect-AuthentikFile -Path $folder -Confirm:$false
    }

    $payload = [ordered]@{
        schemaVersion = 1
        baseUrl       = $BaseUrl
        username      = $Username
        userPk        = $UserPk
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    $secretName = $null
    if ($UseSecretStore) {
        $secretName = 'AuthentikEnvironment-{0}-{1}' -f ([uri]$BaseUrl).Host, $Username
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install
        if (-not $vault -or -not $vault.Available) {
            throw "Vault '$VaultName' is not usable, so the token was not stored."
        }
        Set-TestVaultSecret -VaultName $VaultName -SecretName $secretName -PlainText $Token
        $payload['protection'] = 'SecretStore'
        $payload['vaultName'] = $VaultName
        $payload['secretName'] = $secretName
    }
    else {
        $protected = Protect-AuthentikSecret -PlainText $Token
        $payload['protection'] = $protected.Method
        $payload['tokenProtected'] = $protected.Value
    }

    $json = $payload | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::UTF8.GetBytes($json))
    $null = Protect-AuthentikFile -Path $Path -Confirm:$false

    return [PSCustomObject]@{
        Path       = $Path
        Protection = $payload['protection']
        VaultName  = $(if ($UseSecretStore) { $VaultName } else { $null })
        SecretName = $secretName
    }
}
