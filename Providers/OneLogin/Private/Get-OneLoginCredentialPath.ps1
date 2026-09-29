function Get-OneLoginCredentialPath {
    <#
    .SYNOPSIS
        Returns the file an account's API credential record is kept in

    .DESCRIPTION
        The record lives under the module's per-user credential folder, ~/.testenvironment, which
        Get-TestCredentialRoot creates and restricts to the current user. A path inside the module
        folder would sit in a working tree, one .gitignore mistake away from being pushed.

        One record per account, named by subdomain, so several accounts can be used from one
        machine without overwriting each other.

    .PARAMETER Subdomain
        The account's subdomain, the name in https://<subdomain>.onelogin.com.

    .OUTPUTS
        System.String, the full path to the record.

    .EXAMPLE
        PS> Get-OneLoginCredentialPath -Subdomain contoso

        DESCRIPTION: Resolves the record path, creating the folder if needed
        OUTPUT: C:\Users\you\.testenvironment\contoso.onelogin.json
        USE CASE: Called by Connect-OneLoginEnvironment for -SaveSecret and -UseStoredSecret

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subdomain
    )

    return (Join-Path (Get-TestCredentialRoot) ('{0}.onelogin.json' -f $Subdomain.ToLowerInvariant()))
}
