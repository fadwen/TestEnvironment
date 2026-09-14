function Import-FreeIPACredential {
    <#
    .SYNOPSIS
        Reads the service account credential record and recovers its password

    .DESCRIPTION
        The inverse of Export-FreeIPACredential. Import-TestCredentialRecord reads the record,
        checks the fields FreeIPA's record has to carry, and follows the record to wherever the
        password is; this shapes the result for the connect command, including the pinned CA.

    .PARAMETER Path
        The record to read.

    .PARAMETER VaultPassword
        The vault's password, when the password is in a vault whose password is not a default.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, Password, CaCertificate, Protection, VaultName,
        SecretName, CreatedUtc and Path.

    .EXAMPLE
        PS> $credential = Import-FreeIPACredential -Path $path

        DESCRIPTION: Reads the record and recovers the password
        OUTPUT: The credential with its plaintext password
        USE CASE: Connect-FreeIPAEnvironment -ServiceAccount

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

    $read = Import-TestCredentialRecord -Path $Path -Required baseUrl, username -SecretField 'passwordProtected' `
        -SecretLabel 'password' -MissingRecordMessage 'Run New-TestServiceApp after connecting with a credential.' `
        -VaultPassword $VaultPassword

    return [PSCustomObject]@{
        BaseUrl       = [string]$read.Record.baseUrl
        Username      = [string]$read.Record.username
        Password      = $read.Secret
        CaCertificate = $(if ($read.Record.PSObject.Properties['caCertificate']) { [string]$read.Record.caCertificate } else { $null })
        Protection    = $read.Protection
        VaultName     = $read.VaultName
        SecretName    = $read.SecretName
        CreatedUtc    = $read.CreatedUtc
        Path          = $Path
    }
}
