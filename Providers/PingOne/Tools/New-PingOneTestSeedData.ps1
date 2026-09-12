#Requires -Version 5.1

<#
    .SYNOPSIS
        Regenerates the PingOne provider's seed data CSVs

    .DESCRIPTION
        This is an authoring tool, not part of the module. It runs by hand when the seed data
        needs rebuilding, and the CSVs it writes are the committed artifact - the module never
        calls this, and nothing it reads is needed at run time.

        The data has two halves and the distinction matters:

        - A hand-designed CORE, written into this file and preserved verbatim. These are the
          rows chosen to be awkward in a way that breaks scripts: the population that is
          deliberately empty, the group whose filter matches nothing, the disabled user still
          holding every membership, the public client with no secret, the boolean PingOne makes
          you store as text, and the writing systems that are the only coverage this module has
          for how string handling goes wrong.

          Two states are deliberately absent, because they cannot be seeded and a column that
          is written and silently ignored is worse than no column. verifyStatus belongs to the
          Verify service and is NOT_INITIATED on every user created through the management API.
          An account lock is a separate operation with its own vendor content type, not a field
          on the user. Both were checked against a live environment before being left out.
        - A generated BULK: 311 people read from the module's shared people file,
          Providers/AD/Data/ADUsers.csv, given a population, titles, departments and group
          memberships here. This is what makes pagination real and makes a report that works on
          nineteen users prove something about three hundred.

        Everything here is deterministic. Attributes that need to vary are derived from a
        stable hash of the object's own key rather than from Get-Random, so regenerating
        produces identical files and a diff shows real changes rather than churn.

    .PARAMETER AdDataPath
        The folder holding ADUsers.csv, the people file the 311 bulk users are generated from.
        Defaults to the copy in this repository.

    .PARAMETER OutputPath
        Where to write the CSVs. Defaults to the PingOne provider's own Data folder.

    .PARAMETER WhatIf
        Reports what would be written without writing it.

    .EXAMPLE
        PS> .\New-PingOneTestSeedData.ps1 -Verbose

        DESCRIPTION: Regenerates every PingOne seed CSV
        OUTPUT: Row counts per file
        USE CASE: After changing the core rows, or after the shared people file changes

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$AdDataPath = (Join-Path (Join-Path $PSScriptRoot '..\..\AD') 'Data'),

    [Parameter()]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Data')
)

$ErrorActionPreference = 'Stop'

$AdDataPath = (Resolve-Path -LiteralPath $AdDataPath).ProviderPath
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).ProviderPath
Write-Verbose "Reading the shared people file from $AdDataPath"
Write-Verbose "Writing PingOne data to $OutputPath"

function Get-StableHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return [BitConverter]::ToUInt32($hash, 0)
}

# The same key derivation the other tools use, so a person has the same key in every lab.
function ConvertTo-Key {
    param([string]$Text)
    $clean = ($Text -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

# --------------------------------------------------------------------------------------
# The hand-designed core. Preserved verbatim; never generated.
# --------------------------------------------------------------------------------------

# José held decomposed: an e followed by U+0301 COMBINING ACUTE ACCENT, rather than the single
# precomposed U+00E9 that jnino carries. The two render identically, which is the point, so it
# is built from codepoints rather than typed - an editor that normalised this file on save would
# erase the case without changing a visible character.
$joseDecomposed = 'Jos' + [char]0x0065 + [char]0x0301

# Custom schema attributes. The first is the ownership marker and is not optional: a PingOne
# user has no description field, so without it a seeded user could only be claimed by the
# population holding it, and a user moved out of that population would become unownable.
$coreAttributes = @(
    [ordered]@{ Name = 'zzTestSeedTag'; DisplayName = 'ZZ-TEST seed tag'; Type = 'STRING'; Unique = 'FALSE'; MultiValued = 'FALSE'; Required = 'FALSE'; Tier = 'Core'; Purpose = 'The ownership marker. A PingOne user has no description field to carry one, so the seed creates this and teardown removes it last, after the users that reference it' }
    [ordered]@{ Name = 'labBadgeId'; DisplayName = 'Lab badge id'; Type = 'STRING'; Unique = 'TRUE'; MultiValued = 'FALSE'; Required = 'FALSE'; Tier = 'Core'; Purpose = 'Unique, so a second user carrying the same value is refused by the directory rather than quietly accepted' }
    [ordered]@{ Name = 'labEntitlements'; DisplayName = 'Lab entitlements'; Type = 'STRING'; Unique = 'FALSE'; MultiValued = 'TRUE'; Required = 'FALSE'; Tier = 'Core'; Purpose = 'Multivalued, which a report that assumes one value per attribute silently truncates' }
    [ordered]@{ Name = 'labContractor'; DisplayName = 'Lab contractor'; Type = 'STRING'; Unique = 'FALSE'; MultiValued = 'FALSE'; Required = 'FALSE'; Tier = 'Core'; Purpose = 'A boolean written as text, because PingOne refuses any custom attribute that is not STRING or JSON. The string false is not falsy in PowerShell, so anything casting this rather than comparing it reads every contractor as one' }
    [ordered]@{ Name = 'labProfile'; DisplayName = 'Lab profile'; Type = 'JSON'; Unique = 'FALSE'; MultiValued = 'FALSE'; Required = 'FALSE'; Tier = 'Core'; Purpose = 'The other of the two types PingOne allows on a custom attribute, so a reader that treats every attribute as a string gets an object' }
)

# Populations. None is marked default, and there is no parameter that would: the environment
# already has one, changing it moves where every unassigned user lands, and that is a change to
# the environment rather than to the seed.
$corePopulations = @(
    [ordered]@{ Key = 'staff'; Name = 'Staff'; Description = 'Seeded employees'; Tier = 'Core'; Purpose = 'Holds most of the seeded people, and is the population the dynamic group filters on' }
    [ordered]@{ Key = 'contractors'; Name = 'Contractors'; Description = 'Seeded external people'; Tier = 'Core'; Purpose = 'A second population, so anything that assumes one is wrong' }
    [ordered]@{ Key = 'partners'; Name = 'Partners'; Description = 'Seeded partner identities'; Tier = 'Core'; Purpose = 'A third population outside the staff and contractor split, and the one the population-scoped group points at' }
    [ordered]@{ Key = 'empty-hold'; Name = 'Offboarding Hold'; Description = 'Deliberately empty'; Tier = 'Core'; Purpose = 'Deliberately empty, because an empty population and a failed query look identical in most reports' }
)

# Users. Hand-designed people, each carrying one state or name shape PingOne has to store and
# report correctly.
$coreUsers = @(
    [ordered]@{ Key = 'awhitfield'; GivenName = 'Ada'; FamilyName = 'Whitfield'; Population = 'staff'; Title = 'Chief Executive'; Department = 'Executive'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1001'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki;expenses'; Groups = 'all-staff;leadership'; Tier = 'Core'; Purpose = 'Top of the chain, and the only member of Leadership' }
    [ordered]@{ Key = 'jnino'; GivenName = 'José'; FamilyName = 'Niño'; Population = 'staff'; Title = 'Principal Engineer'; Department = 'Engineering'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1002'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki'; Groups = 'all-staff;engineering;platform'; Tier = 'Core'; Purpose = 'Accented name with an ASCII username, and three-deep group membership' }
    [ordered]@{ Key = 'zmueller'; GivenName = 'Zoë'; FamilyName = 'Müller'; Population = 'staff'; Title = 'Staff Engineer'; Department = 'Engineering'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'B-1003'; Contractor = 'FALSE'; Entitlements = 'vpn'; Groups = 'all-staff;engineering'; Tier = 'Core'; Purpose = 'Accented name, and MFA off where most of the directory has it on' }
    [ordered]@{ Key = 'mbell'; GivenName = 'Marcus'; FamilyName = 'Bell'; Population = 'staff'; Title = 'Account Executive'; Department = 'Sales'; Enabled = 'FALSE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1004'; Contractor = 'FALSE'; Entitlements = 'expenses'; Groups = 'all-staff;sales'; Tier = 'Core'; Purpose = 'Disabled but still in every group; the half-finished offboarding that membership reports count as active' }
    [ordered]@{ Key = 'praghunathan'; GivenName = 'Priya'; FamilyName = 'Raghunathan'; Population = 'staff'; Title = 'Financial Controller'; Department = 'Finance'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1005'; Contractor = 'FALSE'; Entitlements = 'expenses;payroll'; Groups = 'all-staff;finance'; Tier = 'Core'; Purpose = 'In the only group the finance application is assigned to' }
    [ordered]@{ Key = 'talvarez'; GivenName = 'Tomás'; FamilyName = 'Álvarez'; Population = 'staff'; Title = 'Systems Architect'; Department = 'IT'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1006'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki'; Groups = 'all-staff;engineering;sales'; Tier = 'Core'; Purpose = 'In two departments at once, so any per-user department assumption is wrong about him' }
    [ordered]@{ Key = 'hkobayashi'; GivenName = '花'; FamilyName = '小林'; Population = 'contractors'; Title = 'Security Consultant'; Department = 'Contractors'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'C-2001'; Contractor = 'TRUE'; Entitlements = 'wiki'; Groups = 'contractors'; Tier = 'Core'; Purpose = 'Kanji name, a contractor flag that is true, and no membership of the staff chain at all' }
    [ordered]@{ Key = 'ofitzgerald'; GivenName = 'Owen'; FamilyName = 'Fitzgerald'; Population = 'contractors'; Title = 'UX Contractor'; Department = 'Contractors'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = ''; Contractor = 'TRUE'; Entitlements = ''; Groups = 'contractors'; Tier = 'Core'; Purpose = 'No badge id and no entitlements, so a report has to cope with attributes that are simply absent' }
    [ordered]@{ Key = 'svcreporting'; GivenName = 'Reporting'; FamilyName = 'Service'; Population = 'staff'; Title = 'Service Account'; Department = 'IT'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'S-9001'; Contractor = 'FALSE'; Entitlements = ''; Groups = ''; Tier = 'Core'; Purpose = 'A non-human account among the people, in no group at all, which must never be mistaken for the worker application' }
    [ordered]@{ Key = 'pmorel'; GivenName = 'Pascale'; FamilyName = 'Morel'; Population = 'partners'; Title = 'Partner Analyst'; Department = 'Partners'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'P-3001'; Contractor = 'TRUE'; Entitlements = 'wiki'; Groups = 'partners'; Tier = 'Core'; Purpose = 'The only member of the population-scoped group, so adding anyone else to it has to be refused by the directory rather than by this module' }

    # The writing systems. Every username stays plain ASCII: it is what the directory
    # constrains and what the seed prefix is built onto, and the script belongs in the name.
    [ordered]@{ Key = 'jjiang'; GivenName = '俊誉'; FamilyName = '姜'; Population = 'staff'; Title = 'Site Reliability Engineer'; Department = 'Engineering'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1021'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki'; Groups = 'all-staff;engineering;platform'; Tier = 'Core'; Purpose = 'Han name, family name first, joined by an ideographic space that is not U+0020' }
    [ordered]@{ Key = 'tyoshida'; GivenName = '太郎'; FamilyName = '𠮷田'; Population = 'staff'; Title = 'Build Engineer'; Department = 'Engineering'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1022'; Contractor = 'FALSE'; Entitlements = 'vpn'; Groups = 'all-staff;engineering'; Tier = 'Core'; Purpose = 'A surname above the basic plane, so one character is two UTF-16 units and truncation splits it' }
    [ordered]@{ Key = 'dvolkov'; GivenName = 'Дмитрий'; FamilyName = 'Волков'; Population = 'staff'; Title = 'Infrastructure Engineer'; Department = 'IT'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1023'; Contractor = 'FALSE'; Entitlements = 'vpn'; Groups = 'all-staff;engineering'; Tier = 'Core'; Purpose = 'Cyrillic homoglyphs, which a duplicate check made by eye cannot tell from Latin' }
    [ordered]@{ Key = 'gpapadopoulos'; GivenName = 'Γιώργος'; FamilyName = 'Παπαδόπουλος'; Population = 'staff'; Title = 'Financial Analyst'; Department = 'Finance'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'B-1024'; Contractor = 'FALSE'; Entitlements = 'expenses'; Groups = 'all-staff'; Tier = 'Core'; Purpose = 'Greek final sigma, so upper-casing and lower-casing does not return the name. In no department group, because praghunathan is meant to be the only member the finance application admits' }
    [ordered]@{ Key = 'malahmad'; GivenName = 'محمد'; FamilyName = 'الأحمد'; Population = 'staff'; Title = 'Network Engineer'; Department = 'IT'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1025'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki'; Groups = 'all-staff;engineering'; Tier = 'Core'; Purpose = 'Right-to-left, stored in one order and displayed in another wherever it is joined to a Latin username' }
    [ordered]@{ Key = 'jmarchetti'; GivenName = $joseDecomposed; FamilyName = 'Marchetti'; Population = 'staff'; Title = 'Campaign Manager'; Department = 'Marketing'; Enabled = 'TRUE'; MfaEnabled = 'FALSE'; BadgeId = 'B-1026'; Contractor = 'FALSE'; Entitlements = 'wiki'; Groups = 'all-staff'; Tier = 'Core'; Purpose = 'The same José the eye reads on jnino and a different string to every comparison, because this one is stored decomposed' }
    [ordered]@{ Key = 'iisik'; GivenName = 'Irmak'; FamilyName = 'Işık'; Population = 'staff'; Title = 'HR Advisor'; Department = 'Human Resources'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1027'; Contractor = 'FALSE'; Entitlements = 'wiki'; Groups = 'all-staff'; Tier = 'Core'; Purpose = 'Turkish dotted and dotless i, which lower-case differently under a Turkish culture' }
    [ordered]@{ Key = 'jweiss'; GivenName = 'Jürgen'; FamilyName = 'Weiß'; Population = 'staff'; Title = 'Account Executive'; Department = 'Sales'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1028'; Contractor = 'FALSE'; Entitlements = 'expenses'; Groups = 'all-staff;sales'; Tier = 'Core'; Purpose = 'An eszett, which upper-cases into two characters and makes the name longer' }
    [ordered]@{ Key = 'schaudhary'; GivenName = 'सुनीता'; FamilyName = 'चौधरी'; Population = 'staff'; Title = 'Data Engineer'; Department = 'Engineering'; Enabled = 'TRUE'; MfaEnabled = 'TRUE'; BadgeId = 'B-1029'; Contractor = 'FALSE'; Entitlements = 'vpn;wiki'; Groups = 'all-staff;engineering;platform'; Tier = 'Core'; Purpose = 'Devanagari combining vowel signs, so character count and visible marks are different numbers' }
)

# Groups. PingOne has two kinds of membership and the difference is the point: a static group
# holds the users put in it, and a group with a userFilter holds whoever matches, recomputed by
# the directory and not editable by hand.
$coreGroups = @(
    [ordered]@{ Key = 'all-staff'; Name = 'All Staff'; Description = 'Every seeded employee'; Parent = ''; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Top of a three-deep chain, so membership has to resolve transitively rather than one level down' }
    [ordered]@{ Key = 'engineering'; Name = 'Engineering'; Description = 'Engineering department'; Parent = 'all-staff'; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Second level of the chain, and a department with a team beneath it' }
    [ordered]@{ Key = 'platform'; Name = 'Team Platform'; Description = 'Platform engineering team'; Parent = 'engineering'; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Third level; membership here must resolve all the way up to All Staff' }
    [ordered]@{ Key = 'sales'; Name = 'Sales'; Description = 'Sales department'; Parent = 'all-staff'; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'A sibling department with no children, containing a disabled user and a locked one' }
    [ordered]@{ Key = 'finance'; Name = 'Finance'; Description = 'Finance department'; Parent = 'all-staff'; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'The only group the payroll application is assigned to, with exactly one member' }
    [ordered]@{ Key = 'leadership'; Name = 'Leadership'; Description = 'Seeded leadership'; Parent = ''; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Outside the staff chain, with a single member' }
    [ordered]@{ Key = 'contractors'; Name = 'Contractors'; Description = 'External contractors'; Parent = ''; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Outside the staff chain. Its members are the contractors population, but the contractor attribute disagrees: some members are flagged false, and a partner flagged true is not in it' }
    [ordered]@{ Key = 'partners'; Name = 'Partners'; Description = 'Partner identities'; Parent = ''; UserFilter = ''; Population = 'partners'; Tier = 'Core'; Purpose = 'Scoped to a population, so a user outside it cannot be added however hard a script tries' }
    [ordered]@{ Key = 'dyn-staff'; Name = 'Dynamic Staff'; Description = 'Everyone in the staff population'; Parent = ''; UserFilter = 'population'; Population = 'staff'; Tier = 'Core'; Purpose = 'Membership PingOne maintains from a filter, which cannot be edited by hand and is empty until it evaluates' }
    [ordered]@{ Key = 'dyn-nobody'; Name = 'Dynamic Nobody'; Description = 'A filter that matches nothing'; Parent = ''; UserFilter = 'nobody'; Population = ''; Tier = 'Core'; Purpose = 'A filter that is valid and matches nobody, which looks identical to a broken filter in every report' }
    [ordered]@{ Key = 'empty-hold'; Name = 'Offboarding Hold'; Description = 'Deliberately empty'; Parent = ''; UserFilter = ''; Population = ''; Tier = 'Core'; Purpose = 'Deliberately empty, because an empty group and a failed query look identical' }
)

# Resources and the scopes on them. The environment ships two of its own, and this module never
# touches either: they are matched by type, not name, because a name can be edited and a type
# cannot.
$coreResources = @(
    [ordered]@{ Key = 'orders-api'; Name = 'Orders API'; Audience = 'orders-api'; Description = 'Seeded custom resource'; TokenSeconds = '3600'; Scopes = 'orders.read;orders.write;orders.admin'; Tier = 'Core'; Purpose = 'A custom resource with three scopes, which is what an access review is actually reviewing' }
    [ordered]@{ Key = 'reports-api'; Name = 'Reports API'; Audience = 'reports-api'; Description = 'Seeded custom resource'; TokenSeconds = '900'; Scopes = 'reports.read'; Tier = 'Core'; Purpose = 'One scope and a short token lifetime, so two resources do not look alike' }
)

# Applications, across every protocol and type PingOne serves, because the samples ship none.
$coreApplications = @(
    [ordered]@{ Key = 'expenses'; Name = 'Expenses Web'; Type = 'WEB_APP'; Protocol = 'OPENID_CONNECT'; Enabled = 'TRUE'; GrantTypes = 'AUTHORIZATION_CODE'; ResponseTypes = 'CODE'; TokenAuth = 'CLIENT_SECRET_BASIC'; RedirectUris = 'https://expenses.{domain}/callback'; SpEntityId = ''; AcsUrls = ''; Scopes = 'orders-api:orders.read'; AssignGroups = 'all-staff'; Tier = 'Core'; Purpose = 'The ordinary confidential web application, assigned to a group rather than to people' }
    [ordered]@{ Key = 'payroll'; Name = 'Payroll Console'; Type = 'WEB_APP'; Protocol = 'OPENID_CONNECT'; Enabled = 'TRUE'; GrantTypes = 'AUTHORIZATION_CODE'; ResponseTypes = 'CODE'; TokenAuth = 'CLIENT_SECRET_BASIC'; RedirectUris = 'https://payroll.{domain}/callback'; SpEntityId = ''; AcsUrls = ''; Scopes = 'reports-api:reports.read'; AssignGroups = 'finance'; Tier = 'Core'; Purpose = 'Assigned to the one-member group, so an access review that widens by one person is visible' }
    [ordered]@{ Key = 'portal-spa'; Name = 'Partner Portal SPA'; Type = 'SINGLE_PAGE_APP'; Protocol = 'OPENID_CONNECT'; Enabled = 'TRUE'; GrantTypes = 'AUTHORIZATION_CODE'; ResponseTypes = 'CODE'; TokenAuth = 'NONE'; RedirectUris = 'https://portal.{domain}/'; SpEntityId = ''; AcsUrls = ''; Scopes = 'orders-api:orders.read'; AssignGroups = 'partners'; Tier = 'Core'; Purpose = 'A public client with no secret, which is the shape a review most often mistakes for a misconfiguration' }
    [ordered]@{ Key = 'field-native'; Name = 'Field App'; Type = 'NATIVE_APP'; Protocol = 'OPENID_CONNECT'; Enabled = 'TRUE'; GrantTypes = 'AUTHORIZATION_CODE;REFRESH_TOKEN'; ResponseTypes = 'CODE'; TokenAuth = 'NONE'; RedirectUris = 'com.example.field://callback'; SpEntityId = ''; AcsUrls = ''; Scopes = ''; AssignGroups = 'sales'; Tier = 'Core'; Purpose = 'A native client with a custom scheme redirect and a refresh token, which URL validation routinely rejects' }
    [ordered]@{ Key = 'wiki-saml'; Name = 'Wiki SAML'; Type = 'WEB_APP'; Protocol = 'SAML'; Enabled = 'TRUE'; GrantTypes = ''; ResponseTypes = ''; TokenAuth = ''; RedirectUris = ''; SpEntityId = 'https://wiki.{domain}/sp'; AcsUrls = 'https://wiki.{domain}/acs'; Scopes = ''; AssignGroups = 'all-staff'; Tier = 'Core'; Purpose = 'SAML rather than OIDC, so anything that assumes every application has a client id has one that does not' }
    [ordered]@{ Key = 'legacy-disabled'; Name = 'Legacy Console'; Type = 'WEB_APP'; Protocol = 'OPENID_CONNECT'; Enabled = 'FALSE'; GrantTypes = 'AUTHORIZATION_CODE'; ResponseTypes = 'CODE'; TokenAuth = 'CLIENT_SECRET_BASIC'; RedirectUris = 'https://legacy.{domain}/callback'; SpEntityId = ''; AcsUrls = ''; Scopes = ''; AssignGroups = ''; Tier = 'Core'; Purpose = 'Disabled and assigned to nobody, which an inventory still has to list and a review still has to explain' }
)

# --------------------------------------------------------------------------------------
# Bulk, generated from the shared people file
# --------------------------------------------------------------------------------------

$adUsers = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADUsers.csv') -Encoding UTF8)
Write-Verbose "Read $($adUsers.Count) people"

$coreKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreUsers.Key))
$seenKey = @{}
$bulkUsers = [System.Collections.Generic.List[object]]::new()

$bulkPopulations = @('staff', 'contractors', 'partners')

foreach ($adUser in $adUsers) {
    $key = ConvertTo-Key $adUser.SamAccountName
    if (-not $key) { $key = ConvertTo-Key $adUser.Name }
    if (-not $key) { continue }

    # A generated row must never displace a hand-designed one carrying a deliberate edge case.
    if ($coreKeys.Contains($key)) { continue }
    if ($seenKey.ContainsKey($key)) { continue }
    $seenKey[$key] = $true

    $hash = Get-StableHash $key
    $isContractor = ($adUser.EmployeeType -eq 'Contractor')
    $population = if ($isContractor) { 'contractors' } else { $bulkPopulations[$hash % $bulkPopulations.Count] }
    if (-not $isContractor -and $population -ne 'staff' -and ($hash % 7) -ne 0) { $population = 'staff' }

    $groups = @('all-staff')
    switch -Regex ($adUser.Department) {
        'Engineering|IT|Operations' { $groups += 'engineering' }
        'Sales' { $groups += 'sales' }
        # Finance is deliberately left out. It is the one-member group the payroll application is
        # restricted to, and adding every generated accounting user to it erased that: a full seed
        # gave it eight members while its purpose said one.
    }
    if ($population -eq 'contractors') { $groups = @('contractors') }
    if ($population -eq 'partners') { $groups = @('partners') }

    $bulkUsers.Add([ordered]@{
            Key          = $key
            GivenName    = $adUser.GivenName
            FamilyName   = $adUser.Surname
            Population   = $population
            Title        = $adUser.Title
            Department   = $adUser.Department
            Enabled      = $(if ($adUser.Enabled -eq 'False') { 'FALSE' } else { 'TRUE' })
            MfaEnabled   = $(if ((($hash -shr 3) % 10) -lt 7) { 'TRUE' } else { 'FALSE' })
            Verified     = $(if ((($hash -shr 7) % 10) -lt 9) { 'TRUE' } else { 'FALSE' })
            BadgeId      = 'B-{0}' -f (3000 + ($bulkUsers.Count + 1))
            Contractor   = $(if ($isContractor) { 'TRUE' } else { 'FALSE' })
            Entitlements = $(if (($hash % 3) -eq 0) { 'vpn;wiki' } elseif (($hash % 3) -eq 1) { 'wiki' } else { '' })
            Groups       = ($groups -join ';')
            Tier         = 'Bulk'
            Purpose      = "Bulk directory volume ($($adUser.Department))"
        })
}

Write-Verbose "Users: $($coreUsers.Count) core + $($bulkUsers.Count) bulk"

# --------------------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------------------

$outputs = @(
    @{ Name = 'PingOneProfileAttributes'; Rows = $coreAttributes }
    @{ Name = 'PingOnePopulations'; Rows = $corePopulations }
    @{ Name = 'PingOneUsers'; Rows = (@($coreUsers) + @($bulkUsers)) }
    @{ Name = 'PingOneGroups'; Rows = $coreGroups }
    @{ Name = 'PingOneResources'; Rows = $coreResources }
    @{ Name = 'PingOneApplications'; Rows = $coreApplications }
)

foreach ($output in $outputs) {
    $path = Join-Path $OutputPath "$($output.Name).csv"
    if ($PSCmdlet.ShouldProcess($path, 'Write seed data')) {
        @($output.Rows) | ForEach-Object { [PSCustomObject]$_ } |
            Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    }
    Write-Output ('{0,-26} {1,5} rows -> {2}' -f $output.Name, @($output.Rows).Count, $path)
}
