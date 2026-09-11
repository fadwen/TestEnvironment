function Get-FreeIPAServiceApp {
    <#
    .SYNOPSIS
        Reports the stored service account credential and whether it still works

    .DESCRIPTION
        Reads the credential record for a realm and says what this machine would connect as:
        the account, where its password is kept and how it is protected, and whether the
        record pins a certificate authority. Connected, it also checks that the account still
        exists in the realm. With -TestCredential it proves the password by logging in with
        it, which is the check to run before rotating anything when a connect has failed.

        The password itself is never in the output.

    .PARAMETER CredentialPath
        The record to read, when not in the default location.

    .PARAMETER BaseUrl
        The realm whose default record to read, when not connected.

    .PARAMETER VaultPassword
        The SecretStore password, when the record's password is in a vault whose password is
        not a default.

    .PARAMETER TestCredential
        Prove the password authenticates.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, Protection, VaultName, SecretName, PinnedCa,
        CredentialPath, CreatedUtc, AccountExists and CredentialWorks.

    .EXAMPLE
        PS> Get-FreeIPAServiceApp -TestCredential

        DESCRIPTION: Reads the record and proves the password
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

    $connection = Get-FreeIPAConnection -AllowNone
    $resolvedUrl = if ($BaseUrl) { $BaseUrl } elseif ($connection) { $connection.BaseUrl } else { $null }
    if (-not $resolvedUrl -and -not $CredentialPath) {
        throw 'Not connected. Pass -BaseUrl, or -CredentialPath, or connect first.'
    }

    $existingPath = if ($CredentialPath) { $CredentialPath } elseif ($connection) { $connection.CredentialPath } else { $null }
    $recordPath = Get-FreeIPACredentialPath -BaseUrl $(if ($resolvedUrl) { $resolvedUrl } else { 'https://unknown' }) -Path $existingPath

    if (-not (Test-Path -LiteralPath $recordPath)) {
        Write-Warning "No credential record at $recordPath. Run New-TestServiceApp after connecting with a credential."
        return
    }

    $credential = Import-FreeIPACredential -Path $recordPath -VaultPassword $VaultPassword

    $accountExists = $null
    if ($connection) {
        try {
            $shown = Invoke-FreeIPARequest -Method 'user_show' -Arguments $credential.Username -IgnoreError 'NotFound' -Connection $connection
            $accountExists = [bool]$shown
        }
        catch {
            $accountExists = $false
            Write-Verbose "Could not read the account back: $($_.Exception.Message)"
        }
    }

    $credentialWorks = $null
    if ($TestCredential) {
        $probeHttp = $null
        try {
            $probeHttp = New-FreeIPAHttpClient -BaseUrl $credential.BaseUrl -CaCertificate $credential.CaCertificate
            $probe = @{
                BaseUrl = $credential.BaseUrl; Username = $credential.Username; Password = $credential.Password; AuthType = 'ServiceAccount'
                Client = $probeHttp.Client; Cookies = $probeHttp.Cookies
            }
            $login = Connect-FreeIPASession -Connection $probe
            $credentialWorks = [bool]$login.Success
            if (-not $login.Success) { Write-Verbose "Credential test failed: $($login.Reason)" }
        }
        catch {
            $credentialWorks = $false
            Write-Verbose "Credential test failed: $($_.Exception.Message)"
        }
        finally {
            if ($probeHttp) { $probeHttp.Client.Dispose() }
        }
    }

    return [PSCustomObject]@{
        PSTypeName      = 'FreeIPAServiceAppStatus'
        BaseUrl         = $credential.BaseUrl
        Username        = $credential.Username
        Protection      = $credential.Protection
        VaultName       = $credential.VaultName
        SecretName      = $credential.SecretName
        PinnedCa        = [bool]$credential.CaCertificate
        CredentialPath  = $recordPath
        CreatedUtc      = $credential.CreatedUtc
        AccountExists   = $accountExists
        CredentialWorks = $credentialWorks
    }
}
