function Get-OktaUserTypeName {
    <#
    .SYNOPSIS
        Builds the Okta API name for a seeded user type

    .DESCRIPTION
        A user type's API name is not a display name: Okta accepts letters and digits only, so
        the seed prefix cannot be used raw. 'ZZ-TEST-' becomes 'zztest', giving
        'zztestContractor'.

        This exists because two places build the name and they must agree exactly - the function
        that creates the type, and the one that resolves a type's schema path when adding custom
        attributes to it. They were separate expressions, which was survivable only while the
        prefix contained nothing needing removal. The moment the shared prefix acquired a hyphen,
        two copies of "strip what Okta will not take" would have been two chances to strip it
        differently, and the failure mode is a schema written to a type nobody can find.

        The display name is unaffected and keeps the full prefix with its hyphens.

    .PARAMETER Prefix
        The connection's prefix, in either the bare or the trailing-separator form.

    .PARAMETER UserTypeKey
        The type's key from the seed data, for example 'Contractor'.

    .OUTPUTS
        System.String, the API name.

    .EXAMPLE
        PS> Get-OktaUserTypeName -Prefix 'ZZ-TEST-' -UserTypeKey 'Contractor'

        DESCRIPTION: Builds the API name for the seeded contractor type
        OUTPUT: zztestContractor
        USE CASE: Called by New-OktaUserType and Get-OktaSchemaPath

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
        [string]$Prefix,

        # Empty is allowed and returns the sanitised prefix alone, which is what the report uses
        # to recognise a seeded type by the start of its name.
        [Parameter()]
        [AllowEmptyString()]
        [string]$UserTypeKey = ''
    )

    $sanitised = ($Prefix -replace '[^A-Za-z0-9]', '').ToLowerInvariant()

    return '{0}{1}' -f $sanitised, $UserTypeKey
}
