function Resolve-OneLoginDirectoryIdentity {
    <#
    .SYNOPSIS
        Builds the directory-style identifiers a seeded person carries, all of them in the seed's own namespace

    .DESCRIPTION
        A OneLogin account is usually fed from Active Directory, so its people carry an AD user name,
        a UPN, a distinguished name, the groups they are a member of and an employee id. Seeding
        those makes the account look like the ones scripts actually run against, and gives an app
        rule something real to read.

        None of them may name anything outside the seed. A production account's directory connector
        and its provisioning match people by exactly these values - a seeded person carrying the
        sAMAccountName or UPN of a real AD account, or the external id of a real employee, is one a
        sync could link to that account. So every value is built inside the seed's namespace:

        - samaccountname is the prefix and the key, lower case, cut to AD's twenty characters;
        - userprincipalname is the seeded username at the connection's email domain, which is under
          example.com unless somebody who owns another domain chose it;
        - distinguished_name puts the person in OU=<department>,OU=<prefix>Users under DC components
          made from that same domain, and member_of names groups under OU=<prefix>Groups there;
        - external_id is the prefix and the employee id from the data.

        The common name is the person's display name, which is where the writing systems live: an
        ideographic space, a surname above the basic plane, right-to-left script, escaped as RFC 4514
        says and otherwise left exactly as written.

        The comment carries Core's sentence - "Seeded by TestEnvironment. Safe to delete." - for an
        administrator who opens one of these people in a production portal.

    .PARAMETER Row
        The person's row from OneLoginUsers.csv.

    .PARAMETER RoleNameByKey
        The seed data's role names by key, unprefixed.

    .PARAMETER GroupNameByKey
        The seed data's group names by key, unprefixed.

    .PARAMETER Connection
        The connection to take the prefix and email domain from. Defaults to the session's.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary of OneLogin user field names and values.

    .EXAMPLE
        PS> Resolve-OneLoginDirectoryIdentity -Row $row -RoleNameByKey $roles -GroupNameByKey $groups

        DESCRIPTION: Builds the identifiers for one person
        OUTPUT: samaccountname zz-test-jnino, userprincipalname zz-test-jnino@onelogin-lab.example.com, ...
        USE CASE: New-OneLoginUser, and the verifier's expected values

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [hashtable]$RoleNameByKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$GroupNameByKey,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-OneLoginConnection }
    $marker = Get-OneLoginSeedMarker -Prefix $Connection.Prefix
    $prefix = $marker.Prefix

    # RFC 4514: a comma, plus, quote, backslash, angle bracket, semicolon or equals is escaped
    # everywhere, a leading hash or space and a trailing space at the ends.
    $escape = {
        param([string]$Value)
        $escaped = [regex]::Replace($Value, '([,+"\\<>;=])', '\$1')
        if ($escaped.StartsWith('#') -or $escaped.StartsWith(' ')) { $escaped = '\' + $escaped }
        if ($escaped.EndsWith(' ') -and -not $escaped.EndsWith('\ ')) { $escaped = $escaped.Substring(0, $escaped.Length - 1) + '\ ' }
        return $escaped
    }
    $domainComponents = (@(([string]$Connection.EmailDomain).Split('.') | Where-Object { $_ } | ForEach-Object { 'DC={0}' -f (& $escape $_) })) -join ','

    $username = Resolve-OneLoginSeedName -Key $Row.Key -Kind Username -Connection $Connection
    $sam = $username
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }

    $display = [string]$Row.DisplayName
    if (-not $display) { $display = ('{0} {1}' -f $Row.GivenName, $Row.Surname).Trim() }
    $department = if ($Row.Department) { [string]$Row.Department } else { 'Unassigned' }
    $dn = 'CN={0},OU={1},OU={2},{3}' -f (& $escape $display), (& $escape $department), (& $escape ('{0}Users' -f $prefix)), $domainComponents

    $groupDns = New-Object System.Collections.Generic.List[string]
    $names = @(([string]$Row.Roles -split ';') | Where-Object { $_ } | ForEach-Object { $RoleNameByKey[$_] })
    if ($Row.Group) { $names += $GroupNameByKey[[string]$Row.Group] }
    foreach ($name in @($names | Where-Object { $_ })) {
        $groupDns.Add(('CN={0},OU={1},{2}' -f (& $escape ('{0}{1}' -f $prefix, $name)), (& $escape ('{0}Groups' -f $prefix)), $domainComponents))
    }

    $fields = [ordered]@{
        samaccountname        = $sam
        userprincipalname     = Resolve-OneLoginSeedName -Key $Row.Key -Kind Email -Connection $Connection
        distinguished_name    = $dn
        member_of             = ($groupDns -join ';')
        external_id           = $(if ($Row.EmployeeId) { '{0}{1}' -f $prefix, $Row.EmployeeId } else { '' })
        phone                 = [string]$Row.Phone
        preferred_locale_code = [string]$Row.Locale
        comment               = $marker.Description
    }
    return $fields
}
