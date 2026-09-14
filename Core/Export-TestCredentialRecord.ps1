function Export-TestCredentialRecord {
    <#
    .SYNOPSIS
        Writes a provider's credential record, with its secret protected

    .DESCRIPTION
        Every provider that bootstraps a durable identity writes the same kind of record: a few
        public fields naming what the credential is for, and one secret that must never sit on
        disk readable. This is the one place that record is written.

        The secret goes to one of two places, and the record is the authority on which: into a
        SecretStore vault under -UseSecretStore, which is encrypted and portable, or into the
        record itself protected by the platform, which is DPAPI on Windows and unprotected with a
        warning anywhere else. A record written before the vault was proven usable would name a
        secret that was never stored, so the vault is initialised first and the record last.

        The record is written as UTF-8 bytes rather than through Set-Content, which on Windows
        PowerShell prepends a byte order mark that a strict JSON reader rejects. The folder is
        restricted to the current user before the file exists in it, and the file again
        afterwards.

    .PARAMETER Path
        Where to write the record.

    .PARAMETER Record
        The public fields, in the order they should appear. schemaVersion and createdUtc belong
        to the caller; the protection fields are added here.

    .PARAMETER Secret
        The secret to protect.

    .PARAMETER SecretField
        The record field the protected secret is written to when it stays in the record, such as
        tokenProtected or passwordProtected. Import-TestCredentialRecord reads the same field.

    .PARAMETER SecretName
        The name the secret is stored under in the vault, under -UseSecretStore.

    .PARAMETER UseSecretStore
        Keep the secret in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .OUTPUTS
        PSCustomObject with Path, Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Export-TestCredentialRecord -Path $path -Record ([ordered]@{ schemaVersion = 1; baseUrl = $url; username = $name }) -Secret $token -SecretField tokenProtected -SecretName "Lab-$host" -VaultName 'AuthentikEnvironment' -Confirm:$false

        DESCRIPTION: Writes a record with the token DPAPI-protected
        OUTPUT: Path and Protection 'DPAPI'
        USE CASE: Every Export-<Provider>Credential

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Secret',
        Justification = 'The secret arrives in memory as text from an API or a rotation and is protected here before it touches disk.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Record,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Secret,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretField,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the credential record')) {
        return $null
    }

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
        $null = Protect-TestFile -Path $folder -Confirm:$false
    }

    $payload = [ordered]@{}
    foreach ($key in $Record.Keys) { $payload[$key] = $Record[$key] }

    if ($UseSecretStore) {
        if ([string]::IsNullOrWhiteSpace($VaultName)) { throw '-UseSecretStore needs -VaultName.' }
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install -Confirm:$false
        if (-not $vault -or -not $vault.Available) {
            throw "Vault '$VaultName' is not usable, so the secret was not stored."
        }
        $null = Set-TestVaultSecret -VaultName $VaultName -SecretName $SecretName -PlainText $Secret -Confirm:$false
        $payload['protection'] = 'SecretStore'
        $payload['vaultName'] = $VaultName
        $payload['secretName'] = $SecretName
    }
    else {
        $protected = Protect-TestSecret -PlainText $Secret
        $payload['protection'] = $protected.Method
        $payload[$SecretField] = $protected.Value
    }

    $json = $payload | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::UTF8.GetBytes($json))
    $null = Protect-TestFile -Path $Path -Confirm:$false

    return [PSCustomObject]@{
        Path       = $Path
        Protection = $payload['protection']
        VaultName  = $(if ($UseSecretStore) { $VaultName } else { $null })
        SecretName = $(if ($UseSecretStore) { $SecretName } else { $null })
    }
}
