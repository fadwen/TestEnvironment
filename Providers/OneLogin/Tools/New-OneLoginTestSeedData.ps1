#Requires -Version 5.1

<#
    .SYNOPSIS
        Regenerates the OneLogin provider's seed data CSVs

    .DESCRIPTION
        This is an authoring tool, not part of the module. It runs by hand when the seed data
        needs rebuilding, and the CSVs it writes are the committed artifact - the module never
        calls this, and nothing it reads is needed at run time.

        The data has two halves and the distinction matters:

        - A hand-designed CORE, written into this file and preserved verbatim. These are the rows
          chosen to be awkward in a way that breaks scripts: every lifecycle status and state that
          OneLogin keeps once it is set, a suspended manager still managing two people, a rejected
          partner, an unlicensed service account in no group, the boolean OneLogin makes you store
          as text, the mapping that widens a one-person role and the one that is switched off and
          would widen another if anyone switched it on, and the writing systems that are the only
          coverage this module has for how string handling goes wrong.

          Two states are deliberately absent, each checked against a live account: Unactivated, which
          read back as PasswordPending moments after creation, and the Unapproved state, which read
          back as Approved. A column that is written and silently undone is worse than no column.
          Locked is seeded, but not as a status - a status of 3 unlocks itself fifteen minutes later -
          through the lock call, for a year, on a licensed person.

          Ten Core people are Approved, and so hold a user licence. A OneLogin trial has twelve,
          the owner among them, and an account out of licences makes a person Unlicensed without
          saying so, so the Core is sized to leave the owner and one more. The writing-system
          cohort is Unlicensed: what those people test is their names, which no licence changes.

          Only an Approved person whose status is Active, Suspended, PasswordExpired or
          AwaitingPasswordReset can hold a role: OneLogin accepts a grant to anyone else and drops
          it. So the data gives roles to those people only, and every role has at least one of them
          in the Core, which a test holds the data to. A OneLogin role or group has nothing but its
          name to say who made it, so teardown proves one by what it holds; an empty one cannot be
          proved, and would be left behind.

        - A generated BULK: the people read from Providers/AD/Data/ADUsers.csv, given a group by
          office, a manager by the AD chain, and a lifecycle status here. Every one is Unlicensed
          on purpose: three hundred licensed people would not fit a trial and would spend a paid
          account's licences, and an unlicensed person still pages, reports, sits in a group and
          has a manager. They hold no roles, because an unlicensed person cannot. This is what
          makes pagination real and makes a report that works on twenty users prove something
          about three hundred.

        Everything here is deterministic. Attributes that need to vary are derived from a stable
        hash of the object's own key rather than from Get-Random, so regenerating produces
        identical files and a diff shows real changes rather than churn.

    .PARAMETER AdDataPath
        The folder holding ADUsers.csv. Defaults to the copy in this repository.

    .PARAMETER OutputPath
        Where to write the CSVs. Defaults to the OneLogin provider's own Data folder.

    .EXAMPLE
        PS> .\New-OneLoginTestSeedData.ps1 -Verbose

        DESCRIPTION: Regenerates every OneLogin seed CSV
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
Write-Verbose "Reading the AD people from $AdDataPath"
Write-Verbose "Writing OneLogin data to $OutputPath"

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

# The shared people. Every name this generator writes for a person who also exists in the other
# providers comes from Core/Data/SeedPeople.csv, so one identity exists in every lab and a name
# cannot drift between generators. The decomposed Jose lives there too, and a test pins its
# codepoints, because an editor that normalised a file on save would erase the case without
# changing a visible character.
$P = @{}
foreach ($sharedPerson in (Import-Csv -LiteralPath (Join-Path $PSScriptRoot '..\..\..\Core\Data\SeedPeople.csv') -Encoding UTF8)) {
    $P[$sharedPerson.Key] = $sharedPerson
}
# The AD data logs the shared people in under logins of its own - josen for jnino - and every one
# of them is already a core row here. Their AD rows are skipped as people, so nobody exists twice
# under two logins, and remembered by name under the shared key, so a bulk person whose manager
# they are still points at them.
$sharedKeyByName = @{}
foreach ($sharedPerson in $P.Values) { $sharedKeyByName[$sharedPerson.DisplayName] = $sharedPerson.Key }

# Custom user fields. OneLogin's are text and nothing else. The first is the ownership marker and is
# not optional: a OneLogin user has no description, so without it a seeded user could be claimed by
# nothing but its username. Every shortname starts zztest_, because a field has no description
# either and the shortname is the only part of it teardown can check.
$coreAttributes = @(
    [ordered]@{ Shortname = 'zztest_seed_tag'; Name = 'ZZ-TEST seed tag'; Tier = 'Core'; Purpose = 'The ownership marker. A OneLogin user has no description to carry one, so the seed creates this field, writes the tag into it on every user, and teardown removes it last' }
    [ordered]@{ Shortname = 'zztest_badge_id'; Name = 'ZZ-TEST badge id'; Tier = 'Core'; Purpose = 'An identifier outside the directory''s own, absent on some users, so a report has to cope with a field that is simply empty' }
    [ordered]@{ Shortname = 'zztest_contractor'; Name = 'ZZ-TEST contractor'; Tier = 'Core'; Purpose = 'A boolean stored as text, because OneLogin fields are text. The string false is not falsy in PowerShell, so anything casting this rather than comparing it reads every person as a contractor' }
    [ordered]@{ Shortname = 'zztest_cost_center'; Name = 'ZZ-TEST cost center'; Tier = 'Core'; Purpose = 'A value shared by whole departments, which a mapping or report can group on' }
)

# Roles. OneLogin grants app access through roles, so these are where access lives. Four, because a
# trial allows five and the Default role is one of them. Every one has a Core member able to hold it,
# so every tier that includes Core can prove every role at teardown.
$coreRoles = @(
    [ordered]@{ Key = 'all-staff'; Name = 'All Staff'; Tier = 'Core'; Purpose = 'The broad role nearly every licensed employee holds, and the one most apps are granted through; it holds a suspended manager and people whose passwords have lapsed' }
    [ordered]@{ Key = 'engineering'; Name = 'Engineering'; Tier = 'Core'; Purpose = 'A department role, and the one the disabled mapping would hand to every contractor if anybody enabled it' }
    [ordered]@{ Key = 'finance'; Name = 'Finance'; Tier = 'Core'; Purpose = 'One member in the data and a second from the enabled mapping, so who can reach payroll depends on whether mappings have run' }
    [ordered]@{ Key = 'contractors'; Name = 'Contractors'; Tier = 'Core'; Purpose = 'Held by one contractor, while another contractor is licensed, still waiting for a password, and holds nothing' }
)

# Groups. A OneLogin user is in one group at most, and a group is where a security policy is
# applied, so these follow office location the way a real account's do. The seed never gives one a
# policy: it creates none, and attaching somebody else's would change how real people sign in.
$coreGroups = @(
    [ordered]@{ Key = 'seattle-hq'; Name = 'Seattle HQ'; Tier = 'Core'; Purpose = 'Where most of the seeded people are, which makes it the group a per-group report is dominated by' }
    [ordered]@{ Key = 'london'; Name = 'London'; Tier = 'Core'; Purpose = 'An office outside the US, holding a person awaiting a password reset and an unlicensed partner' }
    [ordered]@{ Key = 'new-york'; Name = 'New York'; Tier = 'Core'; Purpose = 'A second US office, so anything that assumes one is wrong' }
    [ordered]@{ Key = 'us-regional'; Name = 'US Regional Offices'; Tier = 'Core'; Purpose = 'Several small offices in one group, including the suspended manager' }
    [ordered]@{ Key = 'remote'; Name = 'Remote Workers'; Tier = 'Core'; Purpose = 'Contractors with no office' }
)

# Users. Hand-designed people, each carrying one lifecycle state, manager shape or name shape
# OneLogin has to store and report correctly. Managers are Core people only, so a Core-only seed
# is complete in itself; the Bulk chain hangs from awhitfield. Ten are Approved; roles go only
# to those whose status lets them hold one.
$coreUsers = @(
    [ordered]@{ Key = 'awhitfield'; GivenName = $P['awhitfield'].GivenName; Surname = $P['awhitfield'].Surname; Title = 'Chief Executive'; Department = 'Executive'; Company = ''; Manager = ''; Status = 'Active'; State = 'Approved'; Group = 'seattle-hq'; Roles = 'all-staff'; BadgeId = 'B-1001'; Contractor = 'FALSE'; CostCenter = 'CC-100'; Tier = 'Core'; Purpose = 'Top of every manager chain' }
    [ordered]@{ Key = 'jnino'; GivenName = $P['jnino'].GivenName; Surname = $P['jnino'].Surname; Title = 'Principal Engineer'; Department = 'Engineering'; Company = ''; Manager = 'awhitfield'; Status = 'Active'; State = 'Approved'; Group = 'seattle-hq'; Roles = 'all-staff;engineering'; BadgeId = 'B-1002'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Accented name with an ASCII username, managing most of the writing-system cohort' }
    [ordered]@{ Key = 'zmueller'; GivenName = $P['zmueller'].GivenName; Surname = $P['zmueller'].Surname; Title = 'Staff Engineer'; Department = 'Engineering'; Company = ''; Manager = 'jnino'; Status = 'PasswordExpired'; State = 'Approved'; Group = 'seattle-hq'; Roles = 'all-staff;engineering'; BadgeId = 'B-1003'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Accented name, and a password that has expired while every role stays in place' }
    [ordered]@{ Key = 'mbell'; GivenName = $P['mbell'].GivenName; Surname = $P['mbell'].Surname; Title = 'Sales Director'; Department = 'Sales'; Company = ''; Manager = 'awhitfield'; Status = 'Suspended'; State = 'Approved'; Group = 'us-regional'; Roles = 'all-staff'; BadgeId = 'B-1004'; Contractor = 'FALSE'; CostCenter = 'CC-300'; Tier = 'Core'; Purpose = 'Suspended but still holding All Staff and still the manager of two people; the half-finished offboarding' }
    [ordered]@{ Key = 'praghunathan'; GivenName = $P['praghunathan'].GivenName; Surname = $P['praghunathan'].Surname; Title = 'Financial Controller'; Department = 'Finance'; Company = ''; Manager = 'awhitfield'; Status = 'Active'; State = 'Approved'; Group = 'seattle-hq'; Roles = 'all-staff;finance'; BadgeId = 'B-1005'; Contractor = 'FALSE'; CostCenter = 'CC-400'; Tier = 'Core'; Purpose = 'The only member of Finance the data names, and the only person the payroll app was meant for' }
    [ordered]@{ Key = 'talvarez'; GivenName = $P['talvarez'].GivenName; Surname = $P['talvarez'].Surname; Title = 'Systems Architect'; Department = 'IT'; Company = ''; Manager = 'jnino'; Status = 'Active'; State = 'Approved'; Group = 'new-york'; Roles = 'all-staff;engineering'; BadgeId = 'B-1006'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'In Engineering by role and IT by department, and the manager of the contractors' }
    [ordered]@{ Key = 'hkobayashi'; GivenName = $P['hkobayashi'].GivenName; Surname = $P['hkobayashi'].Surname; Title = 'Security Consultant'; Department = 'Contractors'; Company = 'Northwind Staffing'; Manager = 'talvarez'; Status = 'Active'; State = 'Approved'; Group = 'remote'; Roles = 'contractors'; BadgeId = 'C-2001'; Contractor = 'TRUE'; CostCenter = 'CC-900'; Tier = 'Core'; Purpose = 'Kanji name, a contractor managed by an employee, and no part of All Staff' }
    [ordered]@{ Key = 'ofitzgerald'; GivenName = $P['ofitzgerald'].GivenName; Surname = $P['ofitzgerald'].Surname; Title = 'UX Contractor'; Department = 'Contractors'; Company = 'Northwind Staffing'; Manager = 'talvarez'; Status = 'Locked'; State = 'Approved'; Group = 'remote'; Roles = 'contractors'; BadgeId = ''; Contractor = 'FALSE'; CostCenter = ''; Tier = 'Core'; Purpose = 'Locked out for a year and still holding the Contractors role; no badge, no cost center, and a contractor field that says false' }
    [ordered]@{ Key = 'nsorensen'; GivenName = $P['nsorensen'].GivenName; Surname = $P['nsorensen'].Surname; Title = 'People Partner'; Department = 'Human Resources'; Company = ''; Manager = 'awhitfield'; Status = 'AwaitingPasswordReset'; State = 'Approved'; Group = 'london'; Roles = 'all-staff'; BadgeId = 'B-1009'; Contractor = 'FALSE'; CostCenter = 'CC-500'; Tier = 'Core'; Purpose = 'A stroked o, and a password reset she has been asked for and not done' }
    [ordered]@{ Key = 'svcreporting'; GivenName = 'Reporting'; Surname = 'Service'; Title = 'Service Account'; Department = 'IT'; Company = ''; Manager = ''; Status = 'Active'; State = 'Unlicensed'; Group = ''; Roles = ''; BadgeId = 'S-9001'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'A non-human account, unlicensed, in no group and no role, which must never be mistaken for the API credential' }
    [ordered]@{ Key = 'pmorel'; GivenName = 'Pascale'; Surname = 'Morel'; Title = 'Partner Analyst'; Department = 'Partners'; Company = 'Fabrikam Partners'; Manager = ''; Status = 'PasswordPending'; State = 'Rejected'; Group = ''; Roles = ''; BadgeId = 'P-3001'; Contractor = 'TRUE'; CostCenter = 'CC-900'; Tier = 'Core'; Purpose = 'Rejected by an administrator and never given a password; present, visible, and unable to do anything. In no group, because OneLogin drops a rejected person''s group as it drops her roles' }
    [ordered]@{ Key = 'lpetit'; GivenName = ('L' + [char]0x00E9 + 'a'); Surname = 'Petit'; Title = 'Partner Consultant'; Department = 'Partners'; Company = 'Fabrikam Partners'; Manager = ''; Status = 'Active'; State = 'Unlicensed'; Group = 'london'; Roles = ''; BadgeId = 'P-3002'; Contractor = 'TRUE'; CostCenter = 'CC-900'; Tier = 'Core'; Purpose = 'Active and unlicensed, which reads as able to sign in to anything that checks status alone' }

    # The writing systems. Every username stays plain ASCII: it is what the directory constrains
    # and what the seed prefix is built onto, and the script belongs in the name.
    [ordered]@{ Key = 'jjiang'; GivenName = $P['jjiang'].GivenName; Surname = $P['jjiang'].Surname; Title = 'Site Reliability Engineer'; Department = 'Engineering'; Company = ''; Manager = 'jnino'; Status = 'Active'; State = 'Unlicensed'; Group = 'seattle-hq'; Roles = ''; BadgeId = 'B-1021'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Han name, family name first, joined by an ideographic space that is not U+0020' }
    [ordered]@{ Key = 'tyoshida'; GivenName = $P['tyoshida'].GivenName; Surname = $P['tyoshida'].Surname; Title = 'Build Engineer'; Department = 'Engineering'; Company = ''; Manager = 'jnino'; Status = 'Active'; State = 'Unlicensed'; Group = 'seattle-hq'; Roles = ''; BadgeId = 'B-1022'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'A surname above the basic plane, so one character is two UTF-16 units and truncation splits it' }
    [ordered]@{ Key = 'dvolkov'; GivenName = $P['dvolkov'].GivenName; Surname = $P['dvolkov'].Surname; Title = 'Infrastructure Engineer'; Department = 'IT'; Company = ''; Manager = 'talvarez'; Status = 'Active'; State = 'Unlicensed'; Group = 'new-york'; Roles = ''; BadgeId = 'B-1023'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Cyrillic homoglyphs, which a duplicate check made by eye cannot tell from Latin' }
    [ordered]@{ Key = 'gpapadopoulos'; GivenName = $P['gpapadopoulos'].GivenName; Surname = $P['gpapadopoulos'].Surname; Title = 'Financial Analyst'; Department = 'Finance'; Company = ''; Manager = 'praghunathan'; Status = 'Active'; State = 'Approved'; Group = 'seattle-hq'; Roles = 'all-staff'; BadgeId = 'B-1024'; Contractor = 'FALSE'; CostCenter = 'CC-400'; Tier = 'Core'; Purpose = 'Greek final sigma, and in Finance by department but not by role, until the enabled mapping puts him there' }
    [ordered]@{ Key = 'malahmad'; GivenName = $P['malahmad'].GivenName; Surname = $P['malahmad'].Surname; Title = 'Network Engineer'; Department = 'IT'; Company = ''; Manager = 'talvarez'; Status = 'Active'; State = 'Unlicensed'; Group = 'seattle-hq'; Roles = ''; BadgeId = 'B-1025'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Right-to-left, stored in one order and displayed in another wherever it is joined to a Latin username' }
    [ordered]@{ Key = 'jmarchetti'; GivenName = $P['jmarchetti'].GivenName; Surname = $P['jmarchetti'].Surname; Title = 'Campaign Manager'; Department = 'Marketing'; Company = ''; Manager = 'mbell'; Status = 'Active'; State = 'Unlicensed'; Group = 'seattle-hq'; Roles = ''; BadgeId = 'B-1026'; Contractor = 'FALSE'; CostCenter = 'CC-600'; Tier = 'Core'; Purpose = 'The same José the eye reads on jnino and a different string to every comparison, because this one is stored decomposed; and reports to a suspended manager' }
    [ordered]@{ Key = 'iisik'; GivenName = $P['iisik'].GivenName; Surname = $P['iisik'].Surname; Title = 'HR Advisor'; Department = 'Human Resources'; Company = ''; Manager = 'nsorensen'; Status = 'Active'; State = 'Unlicensed'; Group = 'london'; Roles = ''; BadgeId = 'B-1027'; Contractor = 'FALSE'; CostCenter = 'CC-500'; Tier = 'Core'; Purpose = 'Turkish dotted and dotless i, which lower-case differently under a Turkish culture' }
    [ordered]@{ Key = 'jweiss'; GivenName = $P['jweiss'].GivenName; Surname = $P['jweiss'].Surname; Title = 'Account Executive'; Department = 'Sales'; Company = ''; Manager = 'mbell'; Status = 'Active'; State = 'Unlicensed'; Group = 'us-regional'; Roles = ''; BadgeId = 'B-1028'; Contractor = 'FALSE'; CostCenter = 'CC-300'; Tier = 'Core'; Purpose = 'An eszett, which upper-cases into two characters, and a second report of the suspended manager' }
    [ordered]@{ Key = 'schaudhary'; GivenName = $P['schaudhary'].GivenName; Surname = $P['schaudhary'].Surname; Title = 'Data Engineer'; Department = 'Engineering'; Company = ''; Manager = 'jnino'; Status = 'Active'; State = 'Unlicensed'; Group = 'seattle-hq'; Roles = ''; BadgeId = 'B-1029'; Contractor = 'FALSE'; CostCenter = 'CC-200'; Tier = 'Core'; Purpose = 'Devanagari combining vowel signs, so character count and visible marks are different numbers' }
)

# The directory-style columns every Core person also carries: the name as a directory displays it,
# which puts the family name first where the person's own name does; an employee id the provider
# writes as external_id behind the seed prefix; a phone number in the 555 range kept for fiction; a
# preferred locale for the people whose names test it; and the MFA factor to pre-enrol, which the
# provider does only where the account offers that factor.
$coreLocale = @{ iisik = 'tr-TR'; hkobayashi = 'ja'; jweiss = 'de' }
$coreMfa = @{ awhitfield = 'Email'; praghunathan = 'Email'; talvarez = 'Email' }
$number = 0
foreach ($row in $coreUsers) {
    $number++
    $row['DisplayName'] = if ($P.ContainsKey($row.Key)) { $P[$row.Key].DisplayName } else { ('{0} {1}' -f $row.GivenName, $row.Surname) }
    $row['EmployeeId'] = 'EMP-C{0:D3}' -f $number
    $row['Phone'] = '(206) 555-{0:D4}' -f (100 + $number)
    $row['Locale'] = if ($coreLocale.ContainsKey($row.Key)) { $coreLocale[$row.Key] } else { '' }
    $row['Mfa'] = if ($coreMfa.ContainsKey($row.Key)) { $coreMfa[$row.Key] } else { '' }
}

# User security policies. OneLogin applies one to everybody in a group, so each is attached to seeded
# groups only and is never the account's default; a group with none falls back to that default, which
# is the comparison a policy review makes. The settings are the password and lockout ones a review
# reads first.
$corePolicies = @(
    [ordered]@{ Key = 'strict-office'; Name = 'Strict Office'; Groups = 'seattle-hq;new-york'; MinimumPasswordLength = '14'; PasswordExpirationDays = '60'; PasswordsRemembered = '24'; MaximumInvalidLoginAttempts = '5'; LockEffectiveMinutes = '30'; Tier = 'Core'; Purpose = 'Long passwords and a lockout for the two biggest offices, so most of the seeded people are under a stricter rule than the account default' }
    [ordered]@{ Key = 'contractor-access'; Name = 'Contractor Access'; Groups = 'remote'; MinimumPasswordLength = '12'; PasswordExpirationDays = '30'; PasswordsRemembered = '6'; MaximumInvalidLoginAttempts = '3'; LockEffectiveMinutes = '60'; Tier = 'Core'; Purpose = 'Shorter password life and a harder lockout for contractors; London and the regional offices have no policy of their own and fall back to the default' }
)

# API authorization servers: OneLogin as the authorization server for an API, with its scopes, the
# claims it puts in a token, and the seeded apps allowed to ask for it. Scopes are value=description,
# claims name=user attribute, clients app key=space-separated scopes; each list separated by |. The
# API's identifier is its Path under the connection's domain.
$coreApiAuthorizations = @(
    [ordered]@{ Key = 'orders-api'; Name = 'Orders API'; Path = 'orders'; TokenMinutes = '60'; Scopes = 'orders:read=Read orders|orders:write=Create and change orders|orders:admin=Administer orders'; Claims = 'department=department|cost_center=custom_attribute_zztest_cost_center'; Clients = 'expenses=orders:read|contractor-portal=orders:read orders:write'; Description = 'Seeded API'; Tier = 'Core'; Purpose = 'Three scopes, one of them granted to no client, and a claim read from a custom field, which is what an API access review actually reads' }
    [ordered]@{ Key = 'reports-api'; Name = 'Reports API'; Path = 'reports'; TokenMinutes = '10'; Scopes = 'reports:read=Read reports'; Claims = 'department=department'; Clients = 'payroll=reports:read'; Description = 'Seeded API'; Tier = 'Core'; Purpose = 'One scope and a ten-minute token, so two servers do not look alike' }
)

# App rules: entitlements an app hands out by role. Each sets the OIDC groups claim from member_of,
# through an expression that keeps the group names; the provider writes that action, so a rule can
# only ever name a seeded role on a seeded app.
$coreAppRules = @(
    [ordered]@{ Key = 'expenses-groups'; App = 'expenses'; Name = 'Directory groups for staff'; Enabled = 'TRUE'; Role = 'all-staff'; Operator = 'ri'; Expression = 'CN=([^,]+)'; Tier = 'Core'; Purpose = 'Enabled: anybody in All Staff gets their directory group names in the token, so a claim changes with group membership' }
    [ordered]@{ Key = 'payroll-dormant'; App = 'payroll'; Name = 'Groups for everyone outside Finance'; Enabled = 'FALSE'; Role = 'finance'; Operator = 'rin'; Expression = '.*'; Tier = 'Core'; Purpose = 'Disabled, and would hand payroll every group of everyone who is not in Finance if anybody enabled it' }
)

# Smart Hooks. One pre-authentication hook, always created disabled and conditioned on a seeded role,
# so even if somebody enabled it, it would run for seeded people alone. It changes nothing: it hands
# back the policy the person already has.
$coreHooks = @(
    [ordered]@{ Key = 'contractor-preauth'; Type = 'pre-authentication'; Role = 'contractors'; Tier = 'Core'; Purpose = 'A disabled pre-authentication hook gated on a seeded role, which a review of what runs at sign-in has to find' }
)

# Self-registration. Always disabled and moderated, with no default role or group, and open only to
# addresses at the lab domain, so no real person could register through it even if it were enabled.
$coreSelfRegistrations = @(
    [ordered]@{ Key = 'partner-signup'; Name = 'Partner Sign-up'; Tier = 'Core'; Purpose = 'A dormant public sign-up page, which an access review has to find because enabling it is one click' }
)

# Apps, across the two protocols and every OIDC client shape the connector offers. Five, because a
# trial allows five. On OneLogin a public client is chosen by token endpoint authentication None,
# and that is PKCE: the connector has no public client without it. Every URL is under the
# connection's own domain.
$coreApps = @(
    [ordered]@{ Key = 'expenses'; Name = 'Expenses Web'; Connector = 'OIDC'; AppType = 'Web'; TokenAuth = 'Basic'; LoginUrl = 'https://expenses.{domain}/'; RedirectUri = 'https://expenses.{domain}/callback'; Audience = ''; ConsumerUrl = ''; Visible = 'TRUE'; Roles = 'all-staff'; Description = 'Seeded confidential web app'; Tier = 'Core'; Purpose = 'The ordinary confidential web app, granted through a role rather than to people' }
    [ordered]@{ Key = 'payroll'; Name = 'Payroll Console'; Connector = 'OIDC'; AppType = 'Web'; TokenAuth = 'Post'; LoginUrl = 'https://payroll.{domain}/'; RedirectUri = 'https://payroll.{domain}/callback'; Audience = ''; ConsumerUrl = ''; Visible = 'TRUE'; Roles = 'finance'; Description = 'Seeded confidential web app'; Tier = 'Core'; Purpose = 'Granted to Finance, whose audience a mapping widens, and posting its secret in the body rather than a header' }
    [ordered]@{ Key = 'contractor-portal'; Name = 'Contractor Portal SPA'; Connector = 'OIDC'; AppType = 'Web'; TokenAuth = 'None'; LoginUrl = ''; RedirectUri = 'https://portal.{domain}/'; Audience = ''; ConsumerUrl = ''; Visible = 'TRUE'; Roles = 'contractors'; Description = 'Seeded public client'; Tier = 'Core'; Purpose = 'A public client with PKCE and no secret, granted only to contractors' }
    [ordered]@{ Key = 'field-native'; Name = 'Field App'; Connector = 'OIDC'; AppType = 'Native'; TokenAuth = 'None'; LoginUrl = ''; RedirectUri = 'com.example.field://callback'; Audience = ''; ConsumerUrl = ''; Visible = 'FALSE'; Roles = ''; Description = 'Seeded native client'; Tier = 'Core'; Purpose = 'A native client with a custom scheme redirect, hidden from the portal and granted to no role, which an inventory still has to list and a review still has to explain' }
    [ordered]@{ Key = 'wiki-saml'; Name = 'Wiki SAML'; Connector = 'SAML'; AppType = ''; TokenAuth = ''; LoginUrl = 'https://wiki.{domain}/login'; RedirectUri = ''; Audience = 'https://wiki.{domain}/sp'; ConsumerUrl = 'https://wiki.{domain}/acs'; Visible = 'TRUE'; Roles = 'all-staff;contractors'; Description = 'Seeded SAML app'; Tier = 'Core'; Purpose = 'SAML rather than OIDC, so anything that assumes every app has a client id has one that does not; granted to two roles' }
)

# Mappings. Every one the seed creates also carries a condition that the seed tag field holds the
# tag, with match all, whatever this file says - the provider adds it and has no switch to leave it
# out - so an enabled mapping can only ever act on seeded people. Conditions here are
# source|operator|value, separated by semicolons.
$coreMappings = @(
    [ordered]@{ Key = 'finance-dept'; Name = 'Finance department gets Finance'; Enabled = 'TRUE'; Conditions = 'department|=|Finance'; Role = 'finance'; Tier = 'Core'; Purpose = 'Enabled, so Finance holds a person the data never lists there, and verification has to judge role membership on what is missing only' }
    [ordered]@{ Key = 'contractor-eng'; Name = 'Contractors get Engineering'; Enabled = 'FALSE'; Conditions = 'custom_attribute_zztest_contractor|=|true'; Role = 'engineering'; Tier = 'Core'; Purpose = 'Disabled, and would put every contractor into Engineering if anyone enabled it; the dormant rule an access review has to find' }
)

# --------------------------------------------------------------------------------------
# Bulk, generated from the AD people
# --------------------------------------------------------------------------------------

$adUsers = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADUsers.csv') -Encoding UTF8)
Write-Verbose "Read $($adUsers.Count) people"

$coreKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreUsers.Key))

# A key for every AD person, by name, so a manager written as a distinguished name resolves.
$keyByName = @{}
foreach ($adUser in $adUsers) {
    if ($sharedKeyByName.ContainsKey($adUser.Name)) { $keyByName[$adUser.Name] = $sharedKeyByName[$adUser.Name]; continue }
    $key = ConvertTo-Key $adUser.SamAccountName
    if (-not $key) { $key = ConvertTo-Key $adUser.Name }
    if ($key) { $keyByName[$adUser.Name] = $key }
}

$groupOf = {
    param($adUser)
    if (-not $adUser.City -or $adUser.Office -like 'Remote*') { return 'remote' }
    switch ($adUser.City) {
        'Seattle' { return 'seattle-hq' }
        'Bellevue' { return 'seattle-hq' }
        'London' { return 'london' }
        'New York' { return 'new-york' }
    }
    return 'us-regional'
}

$seenKey = @{}
$bulkRows = [System.Collections.Generic.List[object]]::new()
$managerOf = @{}

foreach ($adUser in $adUsers) {
    if ($sharedKeyByName.ContainsKey($adUser.Name)) { continue }
    $key = $keyByName[$adUser.Name]
    if (-not $key -or $coreKeys.Contains($key) -or $seenKey.ContainsKey($key)) { continue }
    $seenKey[$key] = $true

    $hash = Get-StableHash $key
    $isContractor = ($adUser.EmployeeType -eq 'Contractor' -or $adUser.Department -eq '1099 Contractor')


    # The chain hangs from awhitfield: the AD data's top person reports to her.
    $manager = 'awhitfield'
    if ($adUser.Manager) {
        $managerName = $adUser.Manager -replace '^CN=', ''
        if ($keyByName.ContainsKey($managerName)) { $manager = $keyByName[$managerName] }
    }
    $managerOf[$key] = $manager

    $bucket = $hash % 100
    $status = if ($adUser.Enabled -eq 'False') { 'Suspended' }
    elseif ($bucket -lt 80) { 'Active' }
    elseif ($bucket -lt 92) { 'PasswordPending' }
    elseif ($bucket -lt 97) { 'PasswordExpired' }
    else { 'AwaitingPasswordReset' }

    $department = if ($adUser.Department) { $adUser.Department } else { 'General' }
    $costCenter = 'CC-{0}' -f (700 + ((Get-StableHash $department) % 200))

    $bulkRows.Add([ordered]@{
            Key        = $key
            GivenName  = $adUser.GivenName
            Surname    = $adUser.Surname
            Title      = $adUser.Title
            Department = $adUser.Department
            Company    = $(if ($isContractor) { 'Northwind Staffing' } else { '' })
            Manager    = $manager
            Status     = $status
            State      = 'Unlicensed'
            Group      = (& $groupOf $adUser)
            Roles      = ''
            BadgeId    = ''
            Contractor = $(if ($isContractor) { 'TRUE' } else { 'FALSE' })
            CostCenter = $costCenter
            DisplayName = $adUser.Name
            EmployeeId = $(if ($adUser.EmployeeID) { $adUser.EmployeeID } else { 'EMP-B{0:D3}' -f ($bulkRows.Count + 1) })
            # Never the AD row's own number, which is not reliably fictional; 555-0100 to 555-0199 is
            # the range reserved for fiction, so no seeded number can reach a real phone.
            Phone      = '(206) 555-01{0:D2}' -f ($hash % 100)
            Locale     = ''
            Mfa        = ''
            Tier       = 'Bulk'
            Purpose    = "Bulk directory volume ($department)"
        })
}

# Badge ids in file order, after the sort, so they read as a sequence.
# Managers before the people who report to them, so the seed can set a manager at creation rather
# than coming back for it. Depth first, then key, so the order is stable.
$bulkByKey = @{}
foreach ($row in $bulkRows) { $bulkByKey[$row.Key] = $row }
$depthOf = {
    param([string]$Key)
    $depth = 0; $cursor = $Key; $guard = 0
    while ($bulkByKey.ContainsKey($cursor) -and $guard -lt 50) { $depth++; $cursor = $managerOf[$cursor]; $guard++ }
    return $depth
}
$sortedBulk = @($bulkRows | Sort-Object -Property @{ Expression = { & $depthOf $_.Key } }, @{ Expression = { $_.Key } })
$badge = 3000
foreach ($row in $sortedBulk) { $badge++; $row.BadgeId = 'B-{0}' -f $badge }

Write-Verbose "Users: $($coreUsers.Count) core + $($sortedBulk.Count) bulk"

# --------------------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------------------

$outputs = @(
    @{ Name = 'OneLoginCustomAttributes'; Rows = $coreAttributes }
    @{ Name = 'OneLoginRoles'; Rows = $coreRoles }
    @{ Name = 'OneLoginGroups'; Rows = $coreGroups }
    @{ Name = 'OneLoginApps'; Rows = $coreApps }
    @{ Name = 'OneLoginMappings'; Rows = $coreMappings }
    @{ Name = 'OneLoginPolicies'; Rows = $corePolicies }
    @{ Name = 'OneLoginApiAuthorizations'; Rows = $coreApiAuthorizations }
    @{ Name = 'OneLoginAppRules'; Rows = $coreAppRules }
    @{ Name = 'OneLoginHooks'; Rows = $coreHooks }
    @{ Name = 'OneLoginSelfRegistrations'; Rows = $coreSelfRegistrations }
    @{ Name = 'OneLoginUsers'; Rows = (@($coreUsers) + @($sortedBulk)) }
)

foreach ($output in $outputs) {
    $path = Join-Path $OutputPath "$($output.Name).csv"
    if ($PSCmdlet.ShouldProcess($path, 'Write seed data')) {
        @($output.Rows) | ForEach-Object { [PSCustomObject]$_ } |
            Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    }
    Write-Output ('{0,-26} {1,5} rows -> {2}' -f $output.Name, @($output.Rows).Count, $path)
}
