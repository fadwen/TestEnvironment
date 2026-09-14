function Import-TestCredentialRecord {
    <#
    .SYNOPSIS
        Reads a provider's credential record and recovers its secret

    .DESCRIPTION
        The inverse of Export-TestCredentialRecord. The record says where the secret is, and this
        follows it: a SecretStore pointer is resolved through the vault it names, a
        platform-protected value is decrypted, and a value stored unprotected is returned with a
        warning that says how to fix that.

        A record that names a vault but not the secret, or claims platform protection and carries
        no protected value, is refused rather than guessed at. So is a record missing any field
        the caller says it needs, and a record that yields an empty secret.

    .PARAMETER Path
        The record to read.

    .PARAMETER Required
        Fields the record must carry, beyond the protection fields.

    .PARAMETER SecretField
        The field the protected secret is in when it stays in the record.

    .PARAMETER SecretLabel
        What the secret is called in messages: token, password, key.

    .PARAMETER MissingRecordMessage
        The message to throw when there is no record at Path; it should say what to run.

    .PARAMETER VaultPassword
        The vault's password, when the secret is in a vault whose password is not a default.

    .OUTPUTS
        PSCustomObject with Record (the parsed JSON), Secret, Protection, VaultName, SecretName,
        CreatedUtc and Path.

    .EXAMPLE
        PS> $read = Import-TestCredentialRecord -Path $path -Required baseUrl, username -SecretField tokenProtected -SecretLabel token -MissingRecordMessage 'Run New-TestServiceApp first.'

        DESCRIPTION: Reads a record and recovers its token
        OUTPUT: The record's fields and the plaintext token
        USE CASE: Every Import-<Provider>Credential

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string[]]$Required = @(),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretField,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SecretLabel = 'secret',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$MissingRecordMessage = 'Run New-TestServiceApp first.',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No credential record at $Path. $MissingRecordMessage"
    }

    # A UTF-8 BOM is legal in a file and illegal in JSON, and something else may have written
    # this file. Strip it rather than failing on it.
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF)
    $record = $null
    try { $record = $text | ConvertFrom-Json }
    catch { throw "'$Path' is not valid JSON: $($_.Exception.Message)" }

    foreach ($field in $Required) {
        if (-not $record.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$record.$field)) {
            throw "The credential record at $Path has no '$field'. Re-run New-TestServiceApp -Force."
        }
    }

    $protection = if ($record.PSObject.Properties['protection'] -and $record.protection) { [string]$record.protection } else { 'None' }

    $secret = switch ($protection) {
        'SecretStore' {
            if (-not $record.PSObject.Properties['vaultName'] -or -not $record.vaultName -or
                -not $record.PSObject.Properties['secretName'] -or -not $record.secretName) {
                throw "'$Path' says the $SecretLabel is in a vault but does not name the vault or secret."
            }
            Get-TestVaultSecret -VaultName $record.vaultName -SecretName $record.secretName -VaultPassword $VaultPassword
        }
        'DPAPI' {
            if (-not $record.PSObject.Properties[$SecretField] -or -not $record.$SecretField) {
                throw "'$Path' is marked DPAPI-protected but carries no protected $SecretLabel."
            }
            Unprotect-TestSecret -Method DPAPI -Value $record.$SecretField
        }
        default {
            if (-not $record.PSObject.Properties[$SecretField]) {
                throw "'$Path' carries no $SecretLabel in any recognised form."
            }
            Write-Warning "The $SecretLabel in $Path is stored unprotected. Re-run New-TestServiceApp -Force -UseSecretStore to encrypt it."
            [string]$record.$SecretField
        }
    }

    if ([string]::IsNullOrWhiteSpace($secret)) {
        throw "The credential record at $Path yielded no $SecretLabel. Re-run New-TestServiceApp -Force."
    }

    return [PSCustomObject]@{
        Record     = $record
        Secret     = $secret
        Protection = $protection
        VaultName  = $(if ($record.PSObject.Properties['vaultName']) { $record.vaultName } else { $null })
        SecretName = $(if ($record.PSObject.Properties['secretName']) { $record.secretName } else { $null })
        CreatedUtc = $(if ($record.PSObject.Properties['createdUtc']) { $record.createdUtc } else { $null })
        Path       = $Path
    }
}
