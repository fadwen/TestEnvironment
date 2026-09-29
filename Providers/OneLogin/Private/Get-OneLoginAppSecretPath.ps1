function Get-OneLoginAppSecretPath {
    <#
    .SYNOPSIS
        Returns the file a seeded app's saved client secret is kept in

    .DESCRIPTION
        One record per app, under the module's per-user credential folder beside the account's own
        API credential record, named by subdomain and app id: <subdomain>.onelogin-app.<id>.json.
        The id, not the name, because a re-created app is a different app with a different secret,
        and teardown matches a record to the app it belongs to by the id alone.

        With -AppId omitted, returns the wildcard pattern that matches every app record for the
        account, which is how teardown finds the records whose app no longer exists.

    .PARAMETER Subdomain
        The account's subdomain.

    .PARAMETER AppId
        The app's id in OneLogin.

    .OUTPUTS
        System.String, the full path to the record, or the pattern for every record of the account.

    .EXAMPLE
        PS> Get-OneLoginAppSecretPath -Subdomain contoso -AppId 4920377

        DESCRIPTION: Resolves one app's record path
        OUTPUT: C:\Users\you\.testenvironment\contoso.onelogin-app.4920377.json
        USE CASE: New-OneLoginApp -SaveAppSecret, and teardown when it deletes that app

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
        [string]$Subdomain,

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$AppId
    )

    $leaf = if ($AppId) { '{0}.onelogin-app.{1}.json' -f $Subdomain.ToLowerInvariant(), $AppId } else { '{0}.onelogin-app.*.json' -f $Subdomain.ToLowerInvariant() }
    return (Join-Path (Get-TestCredentialRoot) $leaf)
}
