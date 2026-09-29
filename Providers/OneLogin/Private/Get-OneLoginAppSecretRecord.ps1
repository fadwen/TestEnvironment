function Get-OneLoginAppSecretRecord {
    <#
    .SYNOPSIS
        Lists the saved app secret records for an account, without reading any secret

    .DESCRIPTION
        Reads each <subdomain>.onelogin-app.<id>.json record under the credential folder and returns
        what it says about itself: the app's id, key and name, the client id, and where the secret
        is kept. The secret is not decrypted here; Get-OneLoginAppCredential does that, for the
        records somebody asks for.

        A record is returned only when its content agrees with its file name - the same account and
        the same app id - so a file that was renamed or written by something else is never taken for
        an app's record and never deleted as one.

    .PARAMETER Subdomain
        The account whose records to list.

    .OUTPUTS
        PSCustomObject per record with Path, Subdomain, AppId, AppKey, AppName, ClientId,
        Protection, VaultName and SecretName.

    .EXAMPLE
        PS> Get-OneLoginAppSecretRecord -Subdomain contoso

        DESCRIPTION: Lists every saved app secret for the contoso account
        OUTPUT: One object per record, with no secret in it
        USE CASE: Teardown, the report, and Get-OneLoginAppCredential

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
        [string]$Subdomain
    )

    $pattern = Get-OneLoginAppSecretPath -Subdomain $Subdomain
    $folder = Split-Path -Path $pattern -Parent
    if (-not (Test-Path -LiteralPath $folder)) { return }

    $account = $Subdomain.ToLowerInvariant()
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter (Split-Path -Path $pattern -Leaf) -File -ErrorAction SilentlyContinue)) {
        $match = [regex]::Match($file.Name, '^(?<account>.+)\.onelogin-app\.(?<id>\d+)\.json$')
        if (-not $match.Success -or $match.Groups['account'].Value -ne $account) { continue }

        $record = $null
        try {
            $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($file.FullName)).TrimStart([char]0xFEFF)
            $record = $text | ConvertFrom-Json
        }
        catch {
            Write-Warning "Skipping $($file.FullName): it is not valid JSON."
            continue
        }
        if ([string]$record.subdomain -ne $account -or [string]$record.appId -ne $match.Groups['id'].Value) {
            Write-Warning "Skipping $($file.FullName): its content names a different account or app than its file name."
            continue
        }

        [PSCustomObject]@{
            Path       = $file.FullName
            Subdomain  = $account
            AppId      = [string]$record.appId
            AppKey     = [string]$record.appKey
            AppName    = [string]$record.appName
            ClientId   = [string]$record.clientId
            Protection = [string]$record.protection
            VaultName  = $(if ($record.PSObject.Properties['vaultName']) { [string]$record.vaultName } else { $null })
            SecretName = $(if ($record.PSObject.Properties['secretName']) { [string]$record.secretName } else { $null })
        }
    }
}
