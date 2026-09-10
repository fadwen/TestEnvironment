function Get-AuthentikServiceApp {
    <#
    .SYNOPSIS
        Reports the stored service account credential and whether it still works

    .DESCRIPTION
        Reads the credential record for an instance and says what this machine would connect
        as: the account, where its token is kept and how it is protected. Connected, it also
        checks that the account still exists in the instance. With -TestCredential it proves
        the token by calling the API with it, which is the check to run before rotating
        anything when a connect has failed.

        The token itself is never in the output.

    .PARAMETER CredentialPath
        The record to read, when not in the default location.

    .PARAMETER BaseUrl
        The instance whose default record to read, when not connected.

    .PARAMETER VaultPassword
        The SecretStore password, when the token is in a vault whose password is not a default.

    .PARAMETER TestCredential
        Prove the token authenticates.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, UserPk, Protection, VaultName, SecretName,
        CredentialPath, CreatedUtc, AccountExists and CredentialWorks.

    .EXAMPLE
        PS> Get-AuthentikServiceApp -TestCredential

        DESCRIPTION: Reads the record and proves the token
        OUTPUT: The account's identifiers with CredentialWorks true or false
        USE CASE: Diagnosing a failed Connect-TestEnvironment -ServiceAccount

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path to a credential record, not a credential.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [string]$BaseUrl,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$TestCredential
    )

    $connection = Get-AuthentikConnection -AllowNone
    $resolvedUrl = if ($BaseUrl) { $BaseUrl } elseif ($connection) { $connection.BaseUrl } else { $null }
    if (-not $resolvedUrl -and -not $CredentialPath) {
        throw 'Not connected. Pass -BaseUrl, or -CredentialPath, or connect first.'
    }

    $existingPath = if ($CredentialPath) { $CredentialPath } elseif ($connection) { $connection.CredentialPath } else { $null }
    $recordPath = Get-AuthentikCredentialPath -BaseUrl $(if ($resolvedUrl) { $resolvedUrl } else { 'https://unknown' }) -Path $existingPath

    if (-not (Test-Path -LiteralPath $recordPath)) {
        Write-Warning "No credential record at $recordPath. Run New-TestServiceApp after connecting with an API token."
        return
    }

    $credential = Import-AuthentikCredential -Path $recordPath -VaultPassword $VaultPassword

    $accountExists = $null
    if ($connection) {
        try {
            $null = Invoke-AuthentikRequest -Method GET -Path "/core/users/$($credential.UserPk)/" -Connection $connection
            $accountExists = $true
        }
        catch {
            $accountExists = $false
            Write-Verbose "Could not read the account back: $($_.Exception.Message)"
        }
    }

    $credentialWorks = $null
    if ($TestCredential) {
        try {
            $probe = @{ BaseUrl = $credential.BaseUrl; AuthorizationHeader = "Bearer $($credential.Token)"; AuthType = 'ServiceAccount' }
            $me = Invoke-AuthentikRequest -Method GET -Path '/core/users/me/' -Connection $probe
            $credentialWorks = [bool]($me -and $me.user -and $me.user.username -eq $credential.Username)
        }
        catch {
            $credentialWorks = $false
            Write-Verbose "Credential test failed: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        PSTypeName      = 'AuthentikServiceAppStatus'
        BaseUrl         = $credential.BaseUrl
        Username        = $credential.Username
        UserPk          = $credential.UserPk
        Protection      = $credential.Protection
        VaultName       = $credential.VaultName
        SecretName      = $credential.SecretName
        CredentialPath  = $recordPath
        CreatedUtc      = $credential.CreatedUtc
        AccountExists   = $accountExists
        CredentialWorks = $credentialWorks
    }
}
