function Import-AuthentikCredential {
    <#
    .SYNOPSIS
        Reads the service account credential record and recovers its token

    .DESCRIPTION
        The inverse of Export-AuthentikCredential. Import-TestCredentialRecord reads the record,
        checks the fields Authentik's record has to carry, and follows the record to wherever the
        token is; this shapes the result for the connect and token commands.

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

    $read = Import-TestCredentialRecord -Path $Path -Required baseUrl, username, userPk -SecretField 'tokenProtected' `
        -SecretLabel 'token' -MissingRecordMessage 'Run New-TestServiceApp after connecting with an API token.' `
        -VaultPassword $VaultPassword

    return [PSCustomObject]@{
        BaseUrl    = [string]$read.Record.baseUrl
        Username   = [string]$read.Record.username
        UserPk     = [int]$read.Record.userPk
        Token      = $read.Secret
        Protection = $read.Protection
        VaultName  = $read.VaultName
        SecretName = $read.SecretName
        CreatedUtc = $read.CreatedUtc
        Path       = $Path
    }
}
