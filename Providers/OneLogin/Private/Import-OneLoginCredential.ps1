function Import-OneLoginCredential {
    <#
    .SYNOPSIS
        Reads an account's API credential record and recovers its client secret

    .DESCRIPTION
        The inverse of Export-OneLoginCredential. Import-TestCredentialRecord reads the record,
        checks the fields OneLogin's record has to carry, and follows the record to wherever the
        secret is; this shapes the result for the connect command.

        The secret comes back as a SecureString, because that is how the connection holds it and
        a plaintext copy would outlive the call that needed it.

    .PARAMETER Path
        The record to read.

    .PARAMETER VaultPassword
        The vault's password, when the secret is in a vault whose password is not a default.

    .OUTPUTS
        PSCustomObject with Subdomain, ClientId, ClientSecret, Protection and Path.

    .EXAMPLE
        PS> $credential = Import-OneLoginCredential -Path (Get-OneLoginCredentialPath -Subdomain contoso)

        DESCRIPTION: Reads the record and recovers the secret
        OUTPUT: The credential with the secret as a SecureString
        USE CASE: Connect-OneLoginEnvironment -UseStoredSecret

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

    $read = Import-TestCredentialRecord -Path $Path -Required subdomain, clientId -SecretField 'clientSecretProtected' `
        -SecretLabel 'client secret' -MissingRecordMessage 'Connect once with -ClientId, -ClientSecret and -SaveSecret first.' `
        -VaultPassword $VaultPassword

    return [PSCustomObject]@{
        Subdomain    = [string]$read.Record.subdomain
        ClientId     = [string]$read.Record.clientId
        ClientSecret = ConvertTo-TestSecureString -PlainText $read.Secret
        Protection   = $read.Protection
        Path         = $Path
    }
}
