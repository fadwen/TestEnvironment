#Requires -Version 5.1

<#
    .SYNOPSIS
        Regenerates the FreeIPA user, group, host and host group seed CSVs from the AD provider's

    .DESCRIPTION
        This is an authoring tool, not part of the module. It runs by hand when the seed data
        needs rebuilding, and the CSVs it writes are the committed artifact - the module never
        calls this at run time. The other seed files under Data\ - the HBAC and sudo rules, the
        RBAC chain, the password policies and the rest - are written by hand and are not
        touched here.

        The data has two halves and the distinction matters:

        - A hand-designed CORE, written into this file and preserved verbatim. These are the
          rows chosen to be awkward in a way that breaks scripts - the accented names, the
          disabled user who keeps memberships and a sudo rule, the staged hire and the
          preserved leaver, the contractor whose principal has expired but whose account was
          never disabled, the user whose authentication type demands a token nobody enrolled,
          the non-POSIX team nested in a POSIX department, the external group that can hold
          only trusted-domain members, the host record nobody claims. Volume does not make any
          of those more likely to be found, so they are never generated.
        - A generated BULK, mapped from the AD provider's people, service accounts, groups and
          devices. This is what makes a listing page, makes transitive membership expensive,
          and makes a report that works on a dozen users prove something about three hundred
          and on eight hosts prove something about four hundred.

        Reusing AD's directory rather than inventing names is deliberate, and it is the same
        choice the Entra and Authentik providers made: the same person and the same machine
        then exist in the AD, Entra, Authentik and FreeIPA labs, so anything matching
        identities across a hybrid boundary - by login, by display name, by badge, by host
        name - has four directories that genuinely correspond.

        FreeIPA is a POSIX directory, so what AD carries as attributes lands in the attributes
        FreeIPA defines for them - title, org unit, employee number and type, manager, phone,
        address - and what AD carries as group membership becomes each user's group list.
        Membership is derived from what the AD data actually says: the department group whose
        name matches the person's department, the employment-type groups for their
        EmployeeType, the management-level groups their title implies, and the office group
        for their Office. Groups nothing in the data can decide - resource, application and
        device access - take a stable sample of the population, so none of them is empty and
        none of them is everybody. AD's access-list groups become non-POSIX groups, because
        nothing on a host needs a GID for them; everything else is POSIX.

        Hosts come from AD's devices. Workstations and servers cross; phones and printers do
        not enrol in an identity domain and stay behind. Each host keeps its description,
        operating system, hardware and MAC address, and joins a host group for its kind and one
        for its office, which is what makes HBAC and sudo rules that name a host group real.

        Everything here is deterministic. Where something has to vary it is derived from a
        stable hash of the object's own key rather than from Get-Random, so regenerating
        produces byte-identical files and a diff shows real changes rather than churn. A test
        under Tests\Unit\Providers\FreeIPA regenerates the files into a temporary folder and
        fails if they differ from what is committed.

    .PARAMETER AdDataPath
        The AD provider's Data folder. Defaults to the one in this repository.

    .PARAMETER OutputPath
        Where to write the CSVs. Defaults to the FreeIPA provider's own Data folder.

    .PARAMETER WhatIf
        Reports what would be written without writing it.

    .EXAMPLE
        PS> .\New-FreeIPATestSeedData.ps1 -Verbose

        DESCRIPTION: Regenerates the four generated seed files at AD parity
        OUTPUT: Row counts per file
        USE CASE: After changing the core rows, or after the AD provider's data changes

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
Write-Verbose "Reading AD data from $AdDataPath"
Write-Verbose "Writing FreeIPA data to $OutputPath"

# A stable hash, so a rebuild produces identical files. Get-Random would reshuffle every
# derived value on every run and make the diff useless.
function Get-StableHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return [BitConverter]::ToUInt32($hash, 0)
}

# The same key derivation the Entra and Authentik tools use, so a person has the same login in
# every lab. FreeIPA lower-cases a login itself, and a group name has to match
# [a-zA-Z0-9_.][a-zA-Z0-9_.-]*, which this satisfies.
function ConvertTo-Key {
    param([string]$Text)
    $clean = ($Text -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

# A host name is a DNS label, so the dashes in an AD computer name survive rather than being
# stripped, and anything that is not a label character becomes one.
function ConvertTo-HostKey {
    param([string]$Text)
    $clean = ($Text.ToLowerInvariant() -replace '[^a-z0-9-]', '-') -replace '-+', '-'
    return $clean.Trim('-')
}

# --------------------------------------------------------------------------------------
# The hand-designed core. Preserved verbatim; never generated.
# --------------------------------------------------------------------------------------

# Parent = the groups this group is a member of, which is how FreeIPA nests: a member group
# rolls its members up into the parent. A row can name more than one, joined by ';'.
# ManagerUsers / ManagerGroups = who may manage the membership without being an administrator.
$coreGroups = @(
    [ordered]@{ Name = 'all-staff'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Organisation'; Description = 'Every internal employee'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'The root of the nesting chain and the broadest HBAC target' }
    [ordered]@{ Name = 'dept-engineering'; Type = 'posix'; GidNumber = ''; Parent = 'all-staff'; Category = 'Department'; Description = 'Engineering department'; ManagerUsers = 'awhitfield'; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Second level of the chain; a department with a team beneath it, and the target of an automember rule' }
    [ordered]@{ Name = 'team-platform'; Type = 'nonposix'; GidNumber = ''; Parent = 'dept-engineering'; Category = 'Team'; Description = 'Platform engineering team'; ManagerUsers = 'jnino'; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Third level; a non-POSIX group nested in a POSIX one, so membership resolves transitively but no GID does' }
    [ordered]@{ Name = 'dept-sales'; Type = 'posix'; GidNumber = ''; Parent = 'all-staff'; Category = 'Department'; Description = 'Sales department'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'A sibling department with no children, whose password policy never expires a password' }
    [ordered]@{ Name = 'dept-finance'; Type = 'posix'; GidNumber = ''; Parent = 'all-staff'; Category = 'Department'; Description = 'Finance department'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'The only group the payroll HBAC rule admits' }
    [ordered]@{ Name = 'contractors'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Population'; Description = 'External contractors'; ManagerUsers = ''; ManagerGroups = 'lab-admins'; Tier = 'Core'; Purpose = 'Deliberately outside the staff chain; filled by an automember rule, and the primary group of the user with no private group' }
    [ordered]@{ Name = 'site-zurich'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Site'; Description = 'Zürich office access'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Non-ASCII description that must survive the round trip; the name itself cannot carry it' }
    [ordered]@{ Name = 'empty-hold'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Utility'; Description = 'A group with no members'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'A report has to handle zero members without special-casing; its automember rule can never match' }
    [ordered]@{ Name = 'lab-admins'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Role'; Description = 'Lab administrators'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Named like an admin group and holding a seeded role, but never a member of admins' }
    [ordered]@{ Name = 'svc-accounts'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Utility'; Description = 'Service accounts'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Every service account, and nothing human' }
    [ordered]@{ Name = 'ext-partners'; Type = 'external'; GidNumber = ''; Parent = 'ext-partners-posix'; Category = 'Trust'; Description = 'Partner accounts from a trusted domain'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'An external group: it can hold only trusted-domain SIDs, so it has no IPA members and no GID' }
    [ordered]@{ Name = 'ext-partners-posix'; Type = 'posix'; GidNumber = ''; Parent = ''; Category = 'Trust'; Description = 'POSIX wrapper for the partner group'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'The POSIX group the external one nests in, which is how a trust grants a GID; it has a member group and no users' }
)

# One public key per user is the common case; two on one user is what a report has to cope
# with. These were generated for the seed and the private halves were discarded.
$keyAda = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA4gGtU71XgUkkWUP5Fml4ryubaKKx3teK8Ss91W3lN+ awhitfield@lab'
$keyJose = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7uuCaVaBovANREx8ZtA/Z/9iYBbOFftGaA5qG4mK4n jnino@lab'
$keyZoe1 = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMik4KnGs+fSxHyHt+78pGwX8LUOCh9Fj5ndgN3HEhWd zmueller1@lab'
$keyZoe2 = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDVvhmrKYrGfAnMpJCRQWV0uGrBrAFGCeYfnJ0RPUiIzab1N4P7hr34K3g2Db2vzMopmdA6B/0J5LVd3beXecSxLg0FGEUA0R8FLbZyR2yTQ7Gd5peGqf/Zk81Cj4Pqj7/JmzZWL/7YCCTR20sV+RflusBXf2C0ioCOqzMEXM0yEArPfwygOEHKqr+SKrBTOpLtslo6JdJ6AoCj9XC+iTyR3Fv1y3Yl1NpOV/B/sr0GkF1MUlueXiGarPOEK1MiEqIiw9O29VabZTK7eB5ai7LtYQvIgiqs5zusWgndO9JO5SClgfAxL47ecbqOrakdLQ6B4YneUJllBIl45y+hikm7 zmueller-legacy@lab'
$keyWeb01 = 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBQGTs1WkWvRhqziUffuLMh0VkbBVSzDH5M9/DtwvDoZcda9s1ykQglhnxyxWaKmqp3pM+3DUQq3sp1FFp7ge74= root@web01'

# Lifecycle is FreeIPA's own: Active and Disabled are the two states of an ordinary entry,
# Staged is an entry under the staging container that user-find never lists, and Preserved is
# a deleted user kept for the audit trail, stripped of every membership. PasswordState is
# what the seed does about the password: None sets nothing, MustChange is what any
# admin-set password is in FreeIPA, and Current means the seed changes it once as the user so
# it is not.
# Jose held decomposed: an e followed by U+0301 COMBINING ACUTE ACCENT, rather than the
# single precomposed U+00E9 that jnino carries. The two render identically, which is the
# point, so it is built from codepoints rather than typed - an editor that normalised this
# file on save would erase the case without changing a visible character.
$joseDecomposed = 'Jos' + [char]0x0065 + [char]0x0301

$coreUsers = @(
    [ordered]@{ Username = 'awhitfield'; GivenName = 'Ada'; Surname = 'Whitfield'; DisplayName = 'Ada Whitfield'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Chief Technology Officer'; OrgUnit = 'Engineering'; Manager = ''; Groups = 'all-staff;dept-engineering;lab-admins'; EmployeeNumber = 'E1001'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = '+1 206 555 0100'; Mobile = '+1 206 555 0101'; Street = '123 Corporate Plaza'; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'en-US'; UserAuthType = ''; PasswordState = 'Current'; PrincipalExpiresInDays = ''; SshPublicKeys = $keyAda; CertMapData = 'CN=Lab Issuing CA,O=IPALAB|CN=Ada Whitfield,O=IPALAB'; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Top of the manager chain; a certificate mapping, a key, and a direct member of a seeded role' }
    [ordered]@{ Username = 'jnino'; GivenName = 'José'; Surname = 'Niño'; DisplayName = 'José Niño'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Platform Engineer'; OrgUnit = 'Engineering'; Manager = 'awhitfield'; Groups = 'all-staff;dept-engineering;team-platform'; EmployeeNumber = 'E1002'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = '+1 206 555 0102'; Mobile = ''; Street = '123 Corporate Plaza'; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'es-ES'; UserAuthType = 'otp'; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = $keyJose; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Accented name; three-deep group membership; must use a token, and has one' }
    [ordered]@{ Username = 'zmueller'; GivenName = 'Zoë'; Surname = 'Müller'; DisplayName = 'Zoë Müller'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Platform Engineer'; OrgUnit = 'Engineering'; Manager = 'jnino'; Groups = 'all-staff;dept-engineering;team-platform;site-zurich'; EmployeeNumber = 'E1003'; EmployeeType = 'Employee'; LoginShell = '/usr/bin/zsh'; HomeDirectory = '/home/zurich/zmueller'; Phone = '+41 44 555 0103'; Mobile = '+41 79 555 0103'; Street = 'Bahnhofstrasse 1'; City = 'Zürich'; State = 'ZH'; PostalCode = '8001'; PreferredLanguage = 'de-CH'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = "$keyZoe1;$keyZoe2"; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Accented name and city; a shell and home that are not the defaults; two keys; overridden by the ID view on the legacy host' }
    [ordered]@{ Username = 'mbell'; GivenName = 'Marcus'; Surname = 'Bell'; DisplayName = 'Marcus Bell'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Sales Director'; OrgUnit = 'Sales'; Manager = 'awhitfield'; Groups = 'all-staff;dept-sales'; EmployeeNumber = 'E1004'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = '+1 713 555 0104'; Mobile = '+1 713 555 0105'; Street = '500 Sales Tower'; City = 'Houston'; State = 'TX'; PostalCode = '77002'; PreferredLanguage = 'en-US'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'A department with no children; holds a token that expired yesterday' }
    # praghunathan authenticates through RADIUS, so she has no IPA password: a password set
    # for her could never be changed as her, because a radius-type user cannot log in with one.
    [ordered]@{ Username = 'praghunathan'; GivenName = 'Priya'; Surname = 'Raghunathan'; DisplayName = 'Priya Raghunathan'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Finance Manager'; OrgUnit = 'Finance'; Manager = 'awhitfield'; Groups = 'all-staff;dept-finance'; EmployeeNumber = 'E1005'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = '+1 206 555 0106'; Mobile = ''; Street = '123 Corporate Plaza'; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'en-US'; UserAuthType = 'radius'; PasswordState = 'None'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = 'legacy-radius'; RadiusUsername = 'praghu'; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'The only user the payroll rule admits, and admitted twice: by name and by group' }
    [ordered]@{ Username = 'talvarez'; GivenName = 'Tomás'; Surname = 'Álvarez'; DisplayName = 'Tomás Álvarez'; Lifecycle = 'Disabled'; Class = 'employee'; Title = 'Account Executive'; OrgUnit = 'Sales'; Manager = 'mbell'; Groups = 'all-staff;dept-sales'; EmployeeNumber = 'E1006'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = '+1 713 555 0107'; Mobile = ''; Street = '500 Sales Tower'; City = 'Houston'; State = 'TX'; PostalCode = '77002'; PreferredLanguage = 'es-MX'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Disabled account that still holds memberships, an HBAC rule, a sudo rule, a disabled token and an override' }
    [ordered]@{ Username = 'hkobayashi'; GivenName = '花'; Surname = '小林'; DisplayName = '小林 花'; Lifecycle = 'Active'; Class = 'contractor'; Title = 'Security Consultant'; OrgUnit = 'Contractors'; Manager = ''; Groups = 'contractors'; EmployeeNumber = 'C2001'; EmployeeType = 'Contractor'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = '+81 90 5555 0201'; Street = ''; City = 'Tokyo'; State = ''; PostalCode = ''; PreferredLanguage = 'ja-JP'; UserAuthType = 'otp'; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Contractor whose authentication type demands a token nobody enrolled, so she cannot log in and nothing says so; kanji name in a gecos that is DirectoryString here' }
    [ordered]@{ Username = 'ofitzgerald'; GivenName = 'Orla'; Surname = 'Fitzgerald'; DisplayName = 'Orla Fitzgerald'; Lifecycle = 'Active'; Class = 'contractor'; Title = 'UX Contractor'; OrgUnit = 'Contractors'; Manager = ''; Groups = 'contractors'; EmployeeNumber = ''; EmployeeType = 'Contractor'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Dublin'; State = ''; PostalCode = ''; PreferredLanguage = 'en-IE'; UserAuthType = 'idp'; PasswordState = 'None'; PrincipalExpiresInDays = '-14'; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = 'github'; IdpUserId = 'ofitzgerald-gh'; NoPrivateGroup = 'TRUE'; PrimaryGroup = 'contractors'; Tier = 'Core'; Purpose = 'No private group, so her primary GID is the contractors group; her principal expired two weeks ago and the account was never disabled' }
    [ordered]@{ Username = 'nsorensen'; GivenName = 'Nadia'; Surname = 'Sørensen'; DisplayName = 'Nadia Sørensen'; Lifecycle = 'Active'; Class = 'intern'; Title = 'Intern'; OrgUnit = 'Engineering'; Manager = 'jnino'; Groups = 'all-staff;dept-engineering'; EmployeeNumber = ''; EmployeeType = 'Intern'; LoginShell = '/bin/bash'; HomeDirectory = '/home/interns/nsorensen'; Phone = ''; Mobile = ''; Street = '123 Corporate Plaza'; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'da-DK'; UserAuthType = ''; PasswordState = 'None'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'No employee number and no password ever set; a report must cope with a missing attribute' }
    [ordered]@{ Username = 'svc-reporting'; GivenName = 'Reporting'; Surname = 'Service'; DisplayName = 'Reporting Service'; Lifecycle = 'Active'; Class = 'service'; Title = 'Reporting service account'; OrgUnit = 'IT'; Manager = 'awhitfield'; Groups = 'svc-accounts'; EmployeeNumber = ''; EmployeeType = 'Service'; LoginShell = '/sbin/nologin'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = ''; State = ''; PostalCode = ''; PreferredLanguage = ''; UserAuthType = ''; PasswordState = 'None'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'A service account among the humans, with no shell to log in with' }
    [ordered]@{ Username = 'lchen'; GivenName = 'Lin'; Surname = 'Chen'; DisplayName = 'Lin Chen'; Lifecycle = 'Staged'; Class = 'employee'; Title = 'Site Reliability Engineer'; OrgUnit = 'Engineering'; Manager = 'awhitfield'; Groups = ''; EmployeeNumber = 'E1011'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'zh-CN'; UserAuthType = ''; PasswordState = 'None'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'A hire who has not started: staged, invisible to user-find, and unable to hold a membership until activated' }
    [ordered]@{ Username = 'rokafor'; GivenName = 'Rita'; Surname = 'Okafor'; DisplayName = 'Rita Okafor'; Lifecycle = 'Preserved'; Class = 'employee'; Title = 'Account Executive'; OrgUnit = 'Sales'; Manager = 'mbell'; Groups = 'all-staff;dept-sales'; EmployeeNumber = 'E1012'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Houston'; State = 'TX'; PostalCode = '77002'; PreferredLanguage = 'en-US'; UserAuthType = ''; PasswordState = 'None'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'A leaver kept for the audit trail: created with these memberships, then preserved, which strips every one of them' }

    # The script cohort, the same nine keys as the Entra and Authentik cores and the same
    # nine people in the AD directory. The username stays a plain POSIX name because FreeIPA
    # constrains it; the writing system lives in the given name, surname and gecos, which are
    # DirectoryString here and hold it without complaint.
    [ordered]@{ Username = 'jjiang'; GivenName = '俊誉'; Surname = '姜'; DisplayName = '姜　俊誉'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Site Reliability Engineer'; OrgUnit = 'Engineering'; Manager = 'jnino'; Groups = 'all-staff;dept-engineering;team-platform'; EmployeeNumber = 'E1021'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'zh-CN'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Han name, family name first, separated by an ideographic space rather than U+0020, so the gecos a client renders is not split by anything that splits on a plain space' }
    [ordered]@{ Username = 'tyoshida'; GivenName = '太郎'; Surname = '𠮷田'; DisplayName = '𠮷田 太郎'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Build Engineer'; OrgUnit = 'Engineering'; Manager = 'jnino'; Groups = 'all-staff;dept-engineering'; EmployeeNumber = 'E1022'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'ja-JP'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'A surname above the basic plane, so one character is two UTF-16 units and Windows PowerShell measures the name one longer than a reader counts' }
    [ordered]@{ Username = 'dvolkov'; GivenName = 'Дмитрий'; Surname = 'Волков'; DisplayName = 'Дмитрий Волков'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Infrastructure Engineer'; OrgUnit = 'Engineering'; Manager = 'awhitfield'; Groups = 'all-staff;dept-engineering'; EmployeeNumber = 'E1023'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'ru-RU'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Cyrillic letters drawn the same as Latin ones, so two accounts can look identical in a console listing and differ in the directory' }
    [ordered]@{ Username = 'gpapadopoulos'; GivenName = 'Γιώργος'; Surname = 'Παπαδόπουλος'; DisplayName = 'Γιώργος Παπαδόπουλος'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Financial Analyst'; OrgUnit = 'Finance'; Manager = 'awhitfield'; Groups = 'all-staff'; EmployeeNumber = 'E1024'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'el-GR'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'In no department group, because praghunathan is meant to be the only member the payroll rule admits. Greek final sigma, a different letter from the medial one, so upper-casing a name and lower-casing it again does not return the name' }
    [ordered]@{ Username = 'malahmad'; GivenName = 'محمد'; Surname = 'الأحمد'; DisplayName = 'محمد الأحمد'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Network Engineer'; OrgUnit = 'Engineering'; Manager = 'awhitfield'; Groups = 'all-staff;dept-engineering'; EmployeeNumber = 'E1025'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'ar-AE'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Right-to-left text, which renders in an order that is not the order it is stored in wherever it is joined to a Latin login or a distinguished name' }
    [ordered]@{ Username = 'jmarchetti'; GivenName = $joseDecomposed; Surname = 'Marchetti'; DisplayName = "$joseDecomposed Marchetti"; Lifecycle = 'Active'; Class = 'employee'; Title = 'Campaign Manager'; OrgUnit = 'Marketing'; Manager = 'mbell'; Groups = 'all-staff'; EmployeeNumber = 'E1026'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'it-IT'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'The same Jose the eye reads on jnino and a different string to every comparison, because this one is stored decomposed' }
    [ordered]@{ Username = 'iisik'; GivenName = 'Irmak'; Surname = 'Işık'; DisplayName = 'Irmak Işık'; Lifecycle = 'Active'; Class = 'employee'; Title = 'HR Advisor'; OrgUnit = 'Human Resources'; Manager = 'awhitfield'; Groups = 'all-staff'; EmployeeNumber = 'E1027'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'tr-TR'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Turkish dotted and dotless i, where lower-casing under a Turkish culture returns a different string from the invariant one, and a login derived that way stops matching' }
    [ordered]@{ Username = 'jweiss'; GivenName = 'Jürgen'; Surname = 'Weiß'; DisplayName = 'Jürgen Weiß'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Account Executive'; OrgUnit = 'Sales'; Manager = 'mbell'; Groups = 'all-staff;dept-sales'; EmployeeNumber = 'E1028'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'de-DE'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'An eszett, which upper-cases into two characters, so the name grows by one every time it is normalised for a comparison' }
    [ordered]@{ Username = 'schaudhary'; GivenName = 'सुनीता'; Surname = 'चौधरी'; DisplayName = 'सुनीता चौधरी'; Lifecycle = 'Active'; Class = 'employee'; Title = 'Data Engineer'; OrgUnit = 'Engineering'; Manager = 'jnino'; Groups = 'all-staff;dept-engineering;team-platform'; EmployeeNumber = 'E1029'; EmployeeType = 'Employee'; LoginShell = '/bin/bash'; HomeDirectory = ''; Phone = ''; Mobile = ''; Street = ''; City = 'Seattle'; State = 'WA'; PostalCode = '98101'; PreferredLanguage = 'hi-IN'; UserAuthType = ''; PasswordState = 'MustChange'; PrincipalExpiresInDays = ''; SshPublicKeys = ''; CertMapData = ''; RadiusProxy = ''; RadiusUsername = ''; IdentityProvider = ''; IdpUserId = ''; NoPrivateGroup = 'FALSE'; PrimaryGroup = ''; Tier = 'Core'; Purpose = 'Devanagari with combining vowel signs, so the count of characters and the count of marks a reader sees are different numbers' }
)

# Parent = the host groups this host group is a member of.
$coreHostgroups = @(
    [ordered]@{ Name = 'all-servers'; Parent = ''; Description = 'Every server'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'The root of the host nesting chain; one host is a direct member rather than reached through a child' }
    [ordered]@{ Name = 'web-servers'; Parent = 'all-servers'; Description = 'Web front ends'; ManagerUsers = 'awhitfield'; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Second level; the target of the engineering HBAC rule and the platform sudo rule' }
    [ordered]@{ Name = 'db-servers'; Parent = 'all-servers'; Description = 'Database servers'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Second level; a sibling with one member' }
    [ordered]@{ Name = 'bastions'; Parent = 'all-servers'; Description = 'Jump hosts'; ManagerUsers = ''; ManagerGroups = 'lab-admins'; Tier = 'Core'; Purpose = 'Second level; every member requires a second factor' }
    [ordered]@{ Name = 'build-runners'; Parent = 'all-servers'; Description = 'CI runners'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Second level; anyone may reboot these under sudo' }
    [ordered]@{ Name = 'legacy-hosts'; Parent = ''; Description = 'Hosts still on an end-of-life OS'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Filled by an automember rule on the operating system; where the ID view applies' }
    [ordered]@{ Name = 'site-zurich-hosts'; Parent = ''; Description = 'Hosts in the Zürich office'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'Filled by an automember rule on locality; non-ASCII description' }
    [ordered]@{ Name = 'empty-hostgroup'; Parent = ''; Description = 'A host group with no members'; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Core'; Purpose = 'A report has to handle zero members; the managed netgroup FreeIPA creates for it is empty too' }
)

# IPAddress = the address FreeIPA writes into the seed's own zones as an A and a PTR record;
# the core sits in 10.213.0.0/24 with the Zürich kiosk in 10.213.9.0/24, and one host has none.
# Hostgroups = the host groups this host is a member of. Every seeded host is a record with no
# keytab: none of them ever enrols, and an inventory has to tell a record from a machine.
$coreHosts = @(
    [ordered]@{ Name = 'web01'; Description = 'Public web front end'; OperatingSystem = 'Rocky Linux 9.4'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack A3'; Class = 'server'; MacAddress = '52:54:00:1a:2b:01'; IPAddress = '10.213.0.11'; SshPublicKey = $keyWeb01; AuthIndicator = ''; ManagedBy = ''; Hostgroups = 'web-servers'; Tier = 'Core'; Purpose = 'The host the HTTP service, the delegation rule and a role membership hang off; carries a host key' }
    [ordered]@{ Name = 'db01'; Description = 'Primary database'; OperatingSystem = 'Red Hat Enterprise Linux 9.4'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack A4'; Class = 'server'; MacAddress = '52:54:00:1a:2b:02'; IPAddress = '10.213.0.12'; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = 'web01'; Hostgroups = 'db-servers'; Tier = 'Core'; Purpose = 'Managed by web01, so that host may fetch its keytab; the payroll rule and the DBA sudo rule name it' }
    [ordered]@{ Name = 'bastion01'; Description = 'SSH jump host'; OperatingSystem = 'Rocky Linux 9.4'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack A1'; Class = 'server'; MacAddress = '52:54:00:1a:2b:03'; IPAddress = '10.213.0.13'; SshPublicKey = ''; AuthIndicator = 'otp'; ManagedBy = ''; Hostgroups = 'bastions'; Tier = 'Core'; Purpose = 'An authentication indicator: a ticket for this host needs a second factor' }
    [ordered]@{ Name = 'legacy01'; Description = 'Legacy reporting box'; OperatingSystem = 'CentOS Linux 7.9'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack B2'; Class = 'server'; MacAddress = '52:54:00:1a:2b:04'; IPAddress = '10.213.0.14'; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = ''; Hostgroups = 'legacy-hosts'; Tier = 'Core'; Purpose = 'End-of-life OS, which the automember rule sees; the ID view applies here and the disabled sudo rule names it' }
    [ordered]@{ Name = 'kiosk01'; Description = 'Zürich reception kiosk'; OperatingSystem = 'Fedora Linux 40'; Platform = 'aarch64'; Locality = 'Zurich, CH'; Location = 'Reception'; Class = 'kiosk'; MacAddress = '52:54:00:1a:2b:05'; IPAddress = '10.213.9.20'; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = ''; Hostgroups = 'site-zurich-hosts'; Tier = 'Core'; Purpose = 'Reached by contractors under HBAC and the shell-escape sudo rule; a member of a netgroup directly' }
    [ordered]@{ Name = 'runner01'; Description = 'CI runner'; OperatingSystem = 'Ubuntu 24.04'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack B1'; Class = 'ci'; MacAddress = '52:54:00:1a:2b:06'; IPAddress = '10.213.0.15'; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = ''; Hostgroups = 'build-runners'; Tier = 'Core'; Purpose = 'A Debian-family host in a Red Hat-family lab' }
    [ordered]@{ Name = 'nfs01'; Description = 'Home directory server'; OperatingSystem = 'TrueNAS SCALE 24.04'; Platform = 'x86_64'; Locality = 'Seattle, WA'; Location = 'Rack A5'; Class = 'server'; MacAddress = '52:54:00:1a:2b:07'; IPAddress = '10.213.0.16'; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = ''; Hostgroups = 'all-servers'; Tier = 'Core'; Purpose = 'A direct member of the root host group rather than of a child; every automount key points here' }
    [ordered]@{ Name = 'orphan01'; Description = ''; OperatingSystem = ''; Platform = ''; Locality = ''; Location = ''; Class = ''; MacAddress = ''; IPAddress = ''; SshPublicKey = ''; AuthIndicator = ''; ManagedBy = ''; Hostgroups = ''; Tier = 'Core'; Purpose = 'No description, no OS, no group and no rule: the record nobody claims' }
)

# --------------------------------------------------------------------------------------
# Bulk groups, mapped from the AD provider, with AD's own nesting
# --------------------------------------------------------------------------------------

$adGroups = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADSecurityGroups.csv') -Encoding UTF8)
Write-Verbose "Read $($adGroups.Count) AD groups"

# AD's access-list categories become non-POSIX groups: nothing on a host needs a GID to decide
# who may reach an application. Everything else - departments, offices, employment types,
# management levels, physical access - is POSIX, because a file on a host might be owned by it.
$nonPosixCategories = @('Application Access', 'Resource Access', 'Device Access')

$coreGroupKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreGroups.Name))
$groupKeyByAdName = @{}
$bulkGroups = [System.Collections.Generic.List[object]]::new()

foreach ($adGroup in $adGroups) {
    $key = ConvertTo-Key $adGroup.GroupName
    # A generated row must never displace a hand-designed one.
    if (-not $key -or $coreGroupKeys.Contains($key)) { continue }
    if ($groupKeyByAdName.ContainsKey($adGroup.GroupName)) { continue }
    $groupKeyByAdName[$adGroup.GroupName] = $key

    $bulkGroups.Add([ordered]@{
            Name        = $key
            Type        = $(if ($adGroup.Category -in $nonPosixCategories) { 'nonposix' } else { 'posix' })
            GidNumber   = ''
            Parent      = ''   # resolved below, once every key exists
            Category    = $adGroup.Category
            Description = $adGroup.Description
            ManagerUsers = ''
            ManagerGroups = ''
            Tier        = 'Bulk'
            Purpose     = "Bulk directory volume, mapped from the AD provider ($($adGroup.Category))"
        })
}

# AD's MemberOfGroup gives real nesting, and a group can name more than one parent. FreeIPA
# nests by membership and a group can be a member of any number of others, so the graph is
# reproduced as it is rather than flattened to a tree.
$bulkGroupByKey = @{}
foreach ($row in $bulkGroups) { $bulkGroupByKey[$row.Name] = $row }

foreach ($adGroup in $adGroups) {
    if (-not $adGroup.MemberOfGroup) { continue }
    $childKey = ConvertTo-Key $adGroup.GroupName
    if (-not $bulkGroupByKey.ContainsKey($childKey)) { continue }

    $parents = foreach ($parentName in @($adGroup.MemberOfGroup -split ';' | Where-Object { $_ })) {
        $parentKey = ConvertTo-Key $parentName.Trim()
        if ($bulkGroupByKey.ContainsKey($parentKey) -and $parentKey -ne $childKey) { $parentKey }
    }
    $bulkGroupByKey[$childKey].Parent = (@($parents | Select-Object -Unique) -join ';')
}

$allGroups = @($coreGroups) + @($bulkGroups)
Write-Verbose "Groups: $($coreGroups.Count) core + $($bulkGroups.Count) bulk = $($allGroups.Count)"

# --------------------------------------------------------------------------------------
# Bulk users, mapped from the AD provider's people and service accounts
# --------------------------------------------------------------------------------------

$adUsers = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADUsers.csv') -Encoding UTF8)
$adServiceAccounts = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADServiceAccounts.csv') -Encoding UTF8)
Write-Verbose "Read $($adUsers.Count) AD users and $($adServiceAccounts.Count) AD service accounts"

$coreUserKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreUsers.Username))
$userKeyByAdName = @{}
$adUserByKey = @{}

foreach ($adUser in $adUsers) {
    $key = ConvertTo-Key $adUser.SamAccountName
    if (-not $key) { $key = ConvertTo-Key $adUser.Name }
    if (-not $key -or $coreUserKeys.Contains($key) -or $userKeyByAdName.ContainsKey($adUser.Name)) { continue }
    $userKeyByAdName[$adUser.Name] = $key
    $adUserByKey[$key] = $adUser
}

# Which bulk group, if any, a person's AD department maps to. Most departments have a group
# of the same name; the few that do not are folded into the nearest one, and a department
# with no sensible home gets none, which is itself a realistic state.
$departmentGroup = @{
    'Sales'                         = 'sales'
    'Sales Engagement Management'   = 'sales'
    'Strategy Consulting'           = 'strategyconsulting'
    'Project Management'            = 'projectmanagement'
    'Operations'                    = 'operations'
    'Content Management Consulting' = 'contentmanagement'
    'Engineering Operations'        = 'engineeringoperations'
    'Marketing'                     = 'marketing'
    'Creative'                      = 'marketing'
    'Accounting'                    = 'accounting'
    'CRM Strategy'                  = 'crmstrategy'
    'Senior Management'             = 'seniormanagement'
    'CVP of IT'                     = 'seniormanagement'
    'Executive'                     = 'executives'
    'Engineering'                   = 'engineering'
    'Human Resources'               = 'humanresources'
}

# Which office group a person's AD office maps to.
$officeGroup = @{
    'Seattle - Main'         = 'seattlemainoffice'
    'Seattle - Engineering'  = 'seattleengineeringoffice'
    'Seattle - Finance'      = 'seattlefinanceoffice'
    'Houston - Sales'        = 'houstonoffice'
    'New York - Strategy'    = 'newyorkoffice'
    'New York - Northeast'   = 'newyorkoffice'
    'Chicago - Central'      = 'chicagooffice'
    'Atlanta - Southeast'    = 'atlantaoffice'
    'Boston - Northeast'     = 'bostonoffice'
    'Los Angeles - West'     = 'losangelesoffice'
    'Richmond - East'        = 'richmondoffice'
    'London - International' = 'londonoffice'
    'Remote - Field Sales'   = 'remoteworkers'
}

# A preferred language follows the office. The lab is mostly American with a London office,
# and a directory that is entirely one locale never exercises the attribute.
$officeLanguage = @{ 'London - International' = 'en-GB' }

$bulkUsers = [System.Collections.Generic.List[object]]::new()
$membership = @{}   # user key -> ordered list of group keys

$addMembership = {
    param($userKey, $groupKey)
    if (-not $groupKey) { return }
    if (-not ($bulkGroupByKey.ContainsKey($groupKey) -or $coreGroupKeys.Contains($groupKey))) { return }
    if (-not $membership.ContainsKey($userKey)) { $membership[$userKey] = [System.Collections.Generic.List[string]]::new() }
    if (-not $membership[$userKey].Contains($groupKey)) { $membership[$userKey].Add($groupKey) }
}

foreach ($key in @($adUserByKey.Keys | Sort-Object)) {
    $adUser = $adUserByKey[$key]
    $isContractor = $adUser.EmployeeType -eq 'Contractor'
    $isIntern = $adUser.EmployeeType -eq 'Intern'
    $title = [string]$adUser.Title

    # The population groups come from employment type. Contractors sit outside the staff
    # chain in both tiers: the core contractors group is what the automember rule fills and
    # the sudo and HBAC rules single out, and AD's own contractor groups sit beside it.
    if ($isContractor) {
        & $addMembership $key 'contractors'
        & $addMembership $key 'allcontractors'
        & $addMembership $key 'contractworkers'
    }
    elseif ($isIntern) {
        & $addMembership $key 'all-staff'
        & $addMembership $key 'allinterns'
        & $addMembership $key 'internemployees'
    }
    else {
        & $addMembership $key 'all-staff'
        & $addMembership $key 'allemployees'
        & $addMembership $key 'fulltimeemployees'
    }

    if ($departmentGroup.ContainsKey($adUser.Department)) { & $addMembership $key $departmentGroup[$adUser.Department] }
    if ($officeGroup.ContainsKey($adUser.Office)) { & $addMembership $key $officeGroup[$adUser.Office] }

    # Management level from the title, which is how the AD data describes those groups.
    if ($title -match '\b(CEO|COO|CFO|CTO)\b') { & $addMembership $key 'clevel'; & $addMembership $key 'vpsandabove' }
    elseif ($title -match '\b(VP|SVP|CVP|Vice President)\b') { & $addMembership $key 'vpsandabove' }
    if ($title -match '\bDirector\b') { & $addMembership $key 'directors' }
    if ($title -match '\bManager\b') { & $addMembership $key 'managers' }

    # Everyone but contractors gets the resources AD says everyone gets.
    if (-not $isContractor) {
        foreach ($everyone in 'emailusers', 'calendarusers', 'internetaccessbasic', 'conferenceroombooking', 'fileshareusers') {
            & $addMembership $key $everyone
        }
        if (-not $isIntern) { & $addMembership $key 'internetaccessfull'; & $addMembership $key 'expensesystemaccess' }
    }

    $class = 'employee'
    if ($isContractor) { $class = 'contractor' } elseif ($isIntern) { $class = 'intern' }
    $language = 'en-US'
    if ($officeLanguage.ContainsKey($adUser.Office)) { $language = $officeLanguage[$adUser.Office] }

    $bulkUsers.Add([ordered]@{
            Username               = $key
            GivenName              = $adUser.GivenName
            Surname                = $adUser.Surname
            DisplayName            = $adUser.Name
            Lifecycle              = $(if ($adUser.Enabled -eq 'False') { 'Disabled' } else { 'Active' })
            Class                  = $class
            Title                  = $title
            OrgUnit                = $adUser.Department
            Manager                = ''   # resolved in a second pass, once every key exists
            Groups                 = ''   # resolved after the sampled groups are filled
            EmployeeNumber         = $adUser.EmployeeID
            EmployeeType           = $adUser.EmployeeType
            LoginShell             = '/bin/bash'
            HomeDirectory          = ''
            Phone                  = $adUser.OfficePhone
            Mobile                 = $adUser.MobilePhone
            Street                 = $adUser.StreetAddress
            City                   = $adUser.City
            State                  = $adUser.State
            PostalCode             = $adUser.PostalCode
            PreferredLanguage      = $language
            UserAuthType           = ''
            PasswordState          = 'None'
            PrincipalExpiresInDays = ''
            SshPublicKeys          = ''
            CertMapData            = ''
            RadiusProxy            = ''
            RadiusUsername         = ''
            IdentityProvider       = ''
            IdpUserId              = ''
            NoPrivateGroup         = 'FALSE'
            PrimaryGroup           = ''
            Tier                   = 'Bulk'
            Purpose                = "Bulk directory volume, mapped from the AD provider ($($adUser.Department))"
        })
}

# The groups nothing in the data can decide take a stable sample of the population, so a
# report meets groups of every size and none of them is empty by accident. empty-hold stays
# empty on purpose.
$assigned = [System.Collections.Generic.HashSet[string]]::new()
foreach ($list in $membership.Values) { foreach ($g in $list) { $null = $assigned.Add($g) } }
$pool = @($bulkUsers | Where-Object { $_.Class -ne 'contractor' } | ForEach-Object { $_.Username })

foreach ($row in $bulkGroups) {
    if ($assigned.Contains($row.Name)) { continue }
    $hash = Get-StableHash $row.Name
    $take = 3 + ($hash % 6)
    foreach ($i in 0..($take - 1)) {
        & $addMembership $pool[($hash + $i * 7) % $pool.Count] $row.Name
    }
}

# Second pass: managers, by AD's CN, which can name someone listed later in the file. A manager
# who does not exist in the bulk points at the top of the core chain rather than nowhere, so
# the chain is real all the way up.
$adManagerByName = @{}
foreach ($adUser in $adUsers) { $adManagerByName[$adUser.Name] = ($adUser.Manager -replace '^CN=', '') }

foreach ($row in $bulkUsers) {
    $managerName = $adManagerByName[$row.DisplayName]
    if ($managerName -and $userKeyByAdName.ContainsKey($managerName)) { $row.Manager = $userKeyByAdName[$managerName] }
    elseif ($managerName) { $row.Manager = 'awhitfield' }

    $groups = @()
    if ($membership.ContainsKey($row.Username)) { $groups = @($membership[$row.Username]) }
    $row.Groups = ($groups -join ';')
}

# Service accounts are users with no shell, in the one group that holds nothing human. AD
# names the person responsible for each, which becomes its manager.
$seenServiceKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($adService in $adServiceAccounts) {
    $key = ConvertTo-HostKey $adService.SamAccountName
    if (-not $key -or $coreUserKeys.Contains($key) -or $adUserByKey.ContainsKey($key) -or -not $seenServiceKeys.Add($key)) { continue }

    $ownerName = $adService.ManagedBy -replace '^CN=', ''
    $manager = ''
    if ($ownerName -and $userKeyByAdName.ContainsKey($ownerName)) { $manager = $userKeyByAdName[$ownerName] }

    $bulkUsers.Add([ordered]@{
            Username               = $key
            GivenName              = $adService.GivenName
            Surname                = $adService.Surname
            DisplayName            = $adService.Name
            Lifecycle              = $(if ($adService.Enabled -eq 'False') { 'Disabled' } else { 'Active' })
            Class                  = 'service'
            Title                  = $adService.Title
            OrgUnit                = $adService.Department
            Manager                = $manager
            Groups                 = 'svc-accounts'
            EmployeeNumber         = $adService.EmployeeID
            EmployeeType           = 'Service'
            LoginShell             = '/sbin/nologin'
            HomeDirectory          = ''
            Phone                  = ''
            Mobile                 = ''
            Street                 = $adService.StreetAddress
            City                   = $adService.City
            State                  = $adService.State
            PostalCode             = $adService.PostalCode
            PreferredLanguage      = ''
            UserAuthType           = ''
            PasswordState          = 'None'
            PrincipalExpiresInDays = ''
            SshPublicKeys          = ''
            CertMapData            = ''
            RadiusProxy            = ''
            RadiusUsername         = ''
            IdentityProvider       = ''
            IdpUserId              = ''
            NoPrivateGroup         = 'FALSE'
            PrimaryGroup           = ''
            Tier                   = 'Bulk'
            Purpose                = "Bulk service account, mapped from the AD provider ($($adService.Application))"
        })
}

$allUsers = @($coreUsers) + @($bulkUsers)
Write-Verbose "Users: $($coreUsers.Count) core + $($bulkUsers.Count) bulk = $($allUsers.Count)"

# --------------------------------------------------------------------------------------
# Bulk host groups and hosts, mapped from the AD provider's devices
# --------------------------------------------------------------------------------------

$adDevices = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADDevices.csv') -Encoding UTF8)
Write-Verbose "Read $($adDevices.Count) AD devices"

# What crosses, and the host group each kind lands in. Phones and printers do not enrol in an
# identity domain, so they stay in AD.
$kindHostgroup = @{
    'Workstation'       = @{ Group = 'workstations'; Class = 'workstation'; Description = 'Workstations and laptops' }
    'File Server'       = @{ Group = 'file-servers'; Class = 'file-server'; Description = 'File servers' }
    'Database Server'   = @{ Group = 'database-servers'; Class = 'database-server'; Description = 'Database servers' }
    'Exchange Server'   = @{ Group = 'mail-servers'; Class = 'mail-server'; Description = 'Mail servers' }
    'Domain Controller' = @{ Group = 'domain-controllers'; Class = 'domain-controller'; Description = 'Domain controllers' }
}

$coreHostgroupKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreHostgroups.Name))
$coreHostKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreHosts.Name))
$bulkHostgroups = [System.Collections.Generic.List[object]]::new()
$bulkHostgroupKeys = [System.Collections.Generic.HashSet[string]]::new()
$bulkHosts = [System.Collections.Generic.List[object]]::new()
$officeSubnets = [ordered]@{}

$addHostgroup = {
    param($key, $parent, $description, $purpose)
    if ($coreHostgroupKeys.Contains($key) -or -not $bulkHostgroupKeys.Add($key)) { return }
    $bulkHostgroups.Add([ordered]@{ Name = $key; Parent = $parent; Description = $description; ManagerUsers = ''; ManagerGroups = ''; Tier = 'Bulk'; Purpose = $purpose })
}

# The server kinds nest under one parent, so a rule that names it reaches every server that
# is not a workstation; the site groups are flat.
& $addHostgroup 'servers' '' 'Every server mapped from the AD provider' 'Bulk host volume, mapped from the AD provider (parent of the server kinds)'
foreach ($kind in @($kindHostgroup.Keys | Sort-Object)) {
    $entry = $kindHostgroup[$kind]
    $parent = ''
    if ($kind -ne 'Workstation') { $parent = 'servers' }
    & $addHostgroup $entry.Group $parent $entry.Description "Bulk host volume, mapped from the AD provider ($kind)"
}

foreach ($adDevice in $adDevices) {
    if (-not $kindHostgroup.ContainsKey($adDevice.DeviceType)) { continue }
    $key = ConvertTo-HostKey $adDevice.DeviceName
    if (-not $key -or $coreHostKeys.Contains($key)) { continue }
    if (@($bulkHosts | Where-Object { $_.Name -eq $key }).Count -gt 0) { continue }

    $kind = $kindHostgroup[$adDevice.DeviceType]
    $siteKey = ''
    if ($adDevice.Office) {
        $siteKey = 'site-' + (ConvertTo-Key $adDevice.Office)
        & $addHostgroup $siteKey '' "Hosts at the $($adDevice.Office) office" 'Bulk host volume, mapped from the AD provider (office)'
    }

    $platform = (@($adDevice.Manufacturer, $adDevice.Model) | Where-Object { $_ }) -join ' '

    # One /24 per office in the seed's /16, from 10.213.10.0 up, hosts numbered from .10 in
    # the order they cross; a big office spills into the next /24. Nothing real should be
    # in 10.213.0.0/16, and the reverse zone the seed creates covers all of it.
    if (-not $officeSubnets.Contains($adDevice.Office)) {
        $officeSubnets[$adDevice.Office] = @{ Base = 10 + 4 * $officeSubnets.Count; Next = 0 }
    }
    $subnet = $officeSubnets[$adDevice.Office]
    $ip = '10.213.{0}.{1}' -f ($subnet.Base + [math]::Floor($subnet.Next / 240)), (10 + ($subnet.Next % 240))
    $subnet.Next++

    # FreeIPA validates a MAC address, and the AD data carries a few that are not one. Those
    # cross with no address rather than failing the host.
    $mac = [string]$adDevice.MACAddress
    if ($mac -notmatch '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$') { $mac = '' }

    $bulkHosts.Add([ordered]@{
            Name            = $key
            Description     = $adDevice.Description
            OperatingSystem = $adDevice.OperatingSystem
            Platform        = $platform
            Locality        = $adDevice.Office
            Location        = ''
            Class           = $kind.Class
            MacAddress      = $mac
            IPAddress       = $ip
            SshPublicKey    = ''
            AuthIndicator   = ''
            ManagedBy       = ''
            Hostgroups      = (@($kind.Group, $siteKey) | Where-Object { $_ }) -join ';'
            Tier            = 'Bulk'
            Purpose         = "Bulk host volume, mapped from the AD provider ($($adDevice.DeviceType))"
        })
}

$allHostgroups = @($coreHostgroups) + @($bulkHostgroups)
$allHosts = @($coreHosts) + @($bulkHosts)
Write-Verbose "Host groups: $($coreHostgroups.Count) core + $($bulkHostgroups.Count) bulk = $($allHostgroups.Count)"
Write-Verbose "Hosts: $($coreHosts.Count) core + $($bulkHosts.Count) bulk = $($allHosts.Count)"

# --------------------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------------------

$outputs = @(
    @{ Name = 'FreeIPAGroups'; Rows = $allGroups }
    @{ Name = 'FreeIPAUsers'; Rows = $allUsers }
    @{ Name = 'FreeIPAHostgroups'; Rows = $allHostgroups }
    @{ Name = 'FreeIPAHosts'; Rows = $allHosts }
)

foreach ($output in $outputs) {
    $path = Join-Path $OutputPath "$($output.Name).csv"
    if (-not $PSCmdlet.ShouldProcess($path, "Write $($output.Rows.Count) rows")) { continue }

    # UTF-8 with a BOM. Several rows carry accented names deliberately, and Windows
    # PowerShell reads a BOM-less file as ANSI and silently changes them.
    $objects = @($output.Rows | ForEach-Object { [PSCustomObject]$_ })
    $csv = ($objects | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($path, $csv + "`r`n", [System.Text.UTF8Encoding]::new($true))

    Write-Output ("{0,-18} {1,5} rows -> {2}" -f $output.Name, $output.Rows.Count, $path)
}
