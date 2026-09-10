function Import-AuthentikCredential {
    <#
    .SYNOPSIS
        Reads the service account credential record and recovers its token

    .DESCRIPTION
        The inverse of Export-AuthentikCredential. The record says where the token is, and
        this reads it from there: the SecretStore vault it names, or the DPAPI-protected value
        in the record itself. A record with no protection at all - written on a platform that
        could not encrypt - is read with a warning, so nobody mistakes it for a safe file.

        A byte order mark is stripped before parsing, because a record edited by hand in an
        editor that adds one would otherwise fail as malformed JSON.

    .PARAMETER Path
        The record to read.

    .PARAMETER VaultPassword
        The vault's password, when the token is in a vault whose password is not a default.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, UserPk, Token, Protection, VaultName, SecretName,
        CreatedUtc and Path.

    .EXAMPLE
        PS> $credential = Import-AuthentikCredential -Path $path

        DESCRIPTION: Reads the record and recovers the token
        OUTPUT: The credential with its plaintext token
        USE CASE: Connect-AuthentikEnvironment -ServiceAccount

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
        [System.Security.SecureString]$VaultPassword
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No service account credential record at $Path. Run New-TestServiceApp after connecting with an API token."
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $record = $text | ConvertFrom-Json

    foreach ($required in 'baseUrl', 'username', 'userPk') {
        if (-not $record.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$record.$required)) {
            throw "The credential record at $Path has no '$required'. Re-run New-TestServiceApp -Force."
        }
    }

    $protection = if ($record.PSObject.Properties['protection'] -and $record.protection) { [string]$record.protection } else { 'None' }

    $token = switch ($protection) {
        'SecretStore' {
            Get-TestVaultSecret -VaultName $record.vaultName -SecretName $record.secretName -VaultPassword $VaultPassword
        }
        'DPAPI' {
            Unprotect-AuthentikSecret -Method DPAPI -Value $record.tokenProtected
        }
        default {
            Write-Warning "The token in $Path is stored unprotected. Re-run New-TestServiceApp -Force -UseSecretStore to encrypt it."
            [string]$record.tokenProtected
        }
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "The credential record at $Path yielded no token. Re-run New-TestServiceApp -Force."
    }

    return [PSCustomObject]@{
        BaseUrl    = [string]$record.baseUrl
        Username   = [string]$record.username
        UserPk     = [int]$record.userPk
        Token      = $token
        Protection = $protection
        VaultName  = $(if ($record.PSObject.Properties['vaultName']) { $record.vaultName } else { $null })
        SecretName = $(if ($record.PSObject.Properties['secretName']) { $record.secretName } else { $null })
        CreatedUtc = $(if ($record.PSObject.Properties['createdUtc']) { $record.createdUtc } else { $null })
        Path       = $Path
    }
}
