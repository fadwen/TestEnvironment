function Get-OneLoginAppCredential {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Returns the saved client id and secret of seeded OneLogin apps as credentials
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Subdomain,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    $account = if ($Subdomain) { $Subdomain } else { (Get-OneLoginConnection).Subdomain }

    foreach ($record in @(Get-OneLoginAppSecretRecord -Subdomain $account)) {
        if ($Key -and $Key -notcontains $record.AppKey) { continue }

        $stored = Import-TestCredentialRecord -Path $record.Path -Required 'appId', 'clientId' -SecretField 'clientSecretProtected' `
            -SecretLabel 'client secret' -MissingRecordMessage 'Seed the app with New-OneLoginApp -SaveAppSecret.' -VaultPassword $VaultPassword
        $secure = ConvertTo-TestSecureString -PlainText $stored.Secret
        $stored = $null

        [PSCustomObject]@{
            Key        = $record.AppKey
            Name       = $record.AppName
            AppId      = $record.AppId
            Subdomain  = $record.Subdomain
            Protection = $record.Protection
            Credential = [PSCredential]::new($record.ClientId, $secure)
        }
    }
}
