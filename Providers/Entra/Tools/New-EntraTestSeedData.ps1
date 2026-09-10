#Requires -Version 5.1

<#
    .SYNOPSIS
        Regenerates the module's seed data CSVs from ADTestEnvironment's, at AD parity

    .DESCRIPTION
        This is an authoring tool, not part of the module. It runs by hand when the seed data
        needs rebuilding, and the CSVs it writes are the committed artifact - the module never
        calls this and has no dependency on ADTestEnvironment at run time.

        The data has two halves and the distinction matters:

        - A hand-designed CORE, preserved verbatim from the existing CSVs. These are the rows
          chosen to be awkward in a way that breaks scripts - the non-ASCII names, the disabled
          user who still holds a licence, the account with no usageLocation, the three-deep
          nesting chain, the group containing only groups. Volume does not make any of those
          more likely to be found, so they are written by hand and never generated.
        - A generated BULK, mapped from ADTestEnvironment's people, machines and groups. This
          is what makes pagination real, makes transitive membership expensive, and makes a
          report that works on nine users prove something about three hundred.

        Reusing AD's directory rather than inventing names is deliberate: the same person then
        exists in both labs, so anything matching identities across a hybrid boundary - by UPN,
        by employeeId, by display name - has two directories that genuinely correspond.

        Everything here is deterministic. Attributes that need to vary (compliance state,
        managed state, usage location) are derived from a stable hash of the object's own key
        rather than from Get-Random, so regenerating produces byte-identical files and a diff
        shows real changes rather than churn.

    .PARAMETER AdDataPath
        Path to ADTestEnvironment's Data folder

    .PARAMETER OutputPath
        Where to write the CSVs. Defaults to the module's own Data folder.

    .PARAMETER WhatIf
        Reports what would be written without writing it

    .EXAMPLE
        PS> .\New-EntraSeedData.ps1

        DESCRIPTION: Regenerates every seed CSV at AD parity
        OUTPUT: Row counts per file
        USE CASE: After changing the core rows, or after ADTestEnvironment's data changes

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$AdDataPath = (Join-Path $PSScriptRoot '..\..\..\Active Directory\ADTestEnvironment\Data'),

    [Parameter()]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Data')
)

$ErrorActionPreference = 'Stop'

$AdDataPath = (Resolve-Path -LiteralPath $AdDataPath).ProviderPath
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).ProviderPath
Write-Verbose "Reading AD data from $AdDataPath"
Write-Verbose "Writing Entra data to $OutputPath"

# A stable hash, so a rebuild produces identical files. Get-Random would reshuffle every
# derived attribute on every run and make the diff useless.
function Get-StableHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return [BitConverter]::ToUInt32($hash, 0)
}

function ConvertTo-Key {
    param([string]$Text)
    $clean = ($Text -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

# --------------------------------------------------------------------------------------
# The hand-designed core. Preserved verbatim; never generated.
# --------------------------------------------------------------------------------------

$coreUsers = @(
    [ordered]@{ Key = 'awhitfield'; GivenName = 'Ada'; Surname = 'Whitfield'; DisplayName = 'Ada Whitfield'; Department = 'Executive'; JobTitle = 'Chief Executive'; UsageLocation = 'US'; AccountEnabled = 'TRUE'; Manager = ''; EmployeeId = 'E1001'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'Top of the manager chain and has no manager of her own; the null that breaks recursive walks' }
    [ordered]@{ Key = 'jnino'; GivenName = 'José'; Surname = 'Niño'; DisplayName = 'José Niño'; Department = 'Engineering'; JobTitle = 'Principal Engineer'; UsageLocation = 'US'; AccountEnabled = 'TRUE'; Manager = 'awhitfield'; EmployeeId = 'E1002'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'Non-ASCII display name with an ASCII UPN, which is what a real directory looks like' }
    [ordered]@{ Key = 'zmueller'; GivenName = 'Zoë'; Surname = 'Müller'; DisplayName = 'Zoë Müller'; Department = 'Engineering'; JobTitle = 'Staff Engineer'; UsageLocation = 'DE'; AccountEnabled = 'TRUE'; Manager = 'jnino'; EmployeeId = '0007'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'Non-ASCII, and an employeeId with leading zeros that any numeric cast destroys' }
    [ordered]@{ Key = 'mbell'; GivenName = 'Marcus'; Surname = 'Bell'; DisplayName = 'Marcus Bell'; Department = 'Sales'; JobTitle = 'Account Executive'; UsageLocation = 'US'; AccountEnabled = 'FALSE'; Manager = 'awhitfield'; EmployeeId = 'E1004'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'Disabled but still licensed and still in groups; the half-finished offboarding' }
    [ordered]@{ Key = 'praghunathan'; GivenName = 'Priya'; Surname = 'Raghunathan'; DisplayName = 'Priya Raghunathan'; Department = 'Finance'; JobTitle = 'Financial Controller'; UsageLocation = 'GB'; AccountEnabled = 'TRUE'; Manager = 'awhitfield'; EmployeeId = 'E1005'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'Holds the same licence both directly and by group, so the assignment path is ambiguous' }
    [ordered]@{ Key = 'talvarez'; GivenName = 'Tomás'; Surname = 'Álvarez'; DisplayName = 'Tomás Álvarez'; Department = 'IT'; JobTitle = 'Systems Architect'; UsageLocation = 'ES'; AccountEnabled = 'TRUE'; Manager = 'jnino'; EmployeeId = 'E1006'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'TRUE'; Tier = 'Core'; Purpose = "In two departments' groups at once, and mail does not match userPrincipalName" }
    [ordered]@{ Key = 'hkobayashi'; GivenName = 'Hana'; Surname = 'Kobayashi'; DisplayName = 'Hana Kobayashi'; Department = 'Human Resources'; JobTitle = 'HR Business Partner'; UsageLocation = 'JP'; AccountEnabled = 'TRUE'; Manager = ''; EmployeeId = 'E1007'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'No manager, no groups, no licence; every empty case in one account' }
    [ordered]@{ Key = 'ofitzgerald'; GivenName = 'Owen'; Surname = 'Fitzgerald'; DisplayName = 'Owen Fitzgerald'; Department = 'Sales'; JobTitle = 'Sales Development'; UsageLocation = ''; AccountEnabled = 'TRUE'; Manager = 'mbell'; EmployeeId = 'E1008'; EmployeeType = 'Employee'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'No usageLocation, so licence assignment fails the way it really does in production' }
    [ordered]@{ Key = 'svcreporting'; GivenName = ''; Surname = ''; DisplayName = 'Reporting Service'; Department = 'Information Technology'; JobTitle = 'Service Account'; UsageLocation = 'US'; AccountEnabled = 'TRUE'; Manager = ''; EmployeeId = ''; EmployeeType = 'Service'; MailDiffersFromUpn = 'FALSE'; Tier = 'Core'; Purpose = 'A non-human account with no given or surname, which name-splitting logic assumes exists' }
)

$coreGroups = @(
    [ordered]@{ Key = 'all-staff'; DisplayName = 'All Staff'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = ''; MemberGroups = 'dept-engineering;dept-sales;dept-finance;dept-it'; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Contains only other groups, so a members query returns no users at all and a transitiveMembers query returns eight' }
    [ordered]@{ Key = 'dept-engineering'; DisplayName = 'Department Engineering'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'jnino;zmueller'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'An ordinary department group and the first level of the nesting chain' }
    [ordered]@{ Key = 'dept-sales'; DisplayName = 'Department Sales'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'mbell;ofitzgerald'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Contains a disabled user, which membership reports routinely count as active' }
    [ordered]@{ Key = 'dept-finance'; DisplayName = 'Department Finance'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'praghunathan'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Single member, and the group that carries the group-based licence' }
    [ordered]@{ Key = 'dept-it'; DisplayName = 'Department IT'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'talvarez'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Tomás is here and in Engineering, so per-user department assumptions are wrong about him' }
    [ordered]@{ Key = 'nested-tier1'; DisplayName = 'Nested Tier 1'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'awhitfield'; MemberGroups = 'nested-tier2'; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Top of a three-deep chain built purely to defeat single-level membership expansion' }
    [ordered]@{ Key = 'nested-tier2'; DisplayName = 'Nested Tier 2'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = ''; MemberGroups = 'nested-tier3'; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Middle tier holding no users of its own, only the tier below it' }
    [ordered]@{ Key = 'nested-tier3'; DisplayName = 'Nested Tier 3'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'talvarez;hkobayashi'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Bottom of the chain; reachable from Tier 1 only transitively' }
    [ordered]@{ Key = 'dyn-engineering'; DisplayName = 'Dynamic Engineering'; GroupKind = 'Security'; MembershipType = 'Dynamic'; MembershipRule = '(user.department -eq "Engineering") and (user.userPrincipalName -startsWith "{Prefix}")'; Members = ''; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Membership Entra maintains, which is empty until it evaluates and cannot be edited by hand' }
    [ordered]@{ Key = 'dyn-disabled'; DisplayName = 'Dynamic Disabled Accounts'; GroupKind = 'Security'; MembershipType = 'Dynamic'; MembershipRule = '(user.accountEnabled -eq false) and (user.userPrincipalName -startsWith "{Prefix}")'; Members = ''; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Matches on a false boolean, which is the value a rule written against truthiness silently drops' }
    [ordered]@{ Key = 'm365-collab'; DisplayName = 'Collaboration Workspace'; GroupKind = 'Unified'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'jnino;praghunathan'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'A Microsoft 365 group, which carries a mailbox and a SharePoint site a security group does not' }
    [ordered]@{ Key = 'lic-powerbi'; DisplayName = 'Licence Power BI'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'praghunathan;mbell'; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Carries a licence for its members to inherit, and so cannot be deleted until it is removed' }
    [ordered]@{ Key = 'role-support'; DisplayName = 'Role Assignable Support'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = 'svcreporting'; MemberGroups = ''; IsAssignableToRole = 'TRUE'; Tier = 'Core'; Purpose = 'Role-assignable, which is immutable after creation and changes how the group is protected' }
    [ordered]@{ Key = 'empty-hold'; DisplayName = 'Offboarding Hold'; GroupKind = 'Security'; MembershipType = 'Assigned'; MembershipRule = ''; Members = ''; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'Deliberately empty, because an empty group and a failed query look identical in most reports' }
)

$coreDevices = @(
    [ordered]@{ Key = 'win-compliant'; DisplayName = 'Workstation Windows Compliant'; OperatingSystem = 'Windows'; OperatingSystemVersion = '10.0.26100'; IsCompliant = 'TRUE'; IsManaged = 'TRUE'; AccountEnabled = 'TRUE'; RegisteredOwner = 'jnino'; Tier = 'Core'; Purpose = 'The baseline a compliance report should pass, owned by an active user' }
    [ordered]@{ Key = 'win-noncompliant'; DisplayName = 'Workstation Windows Noncompliant'; OperatingSystem = 'Windows'; OperatingSystemVersion = '10.0.22631'; IsCompliant = 'FALSE'; IsManaged = 'TRUE'; AccountEnabled = 'TRUE'; RegisteredOwner = 'zmueller'; Tier = 'Core'; Purpose = 'Managed and failing compliance, which is the state a device policy is meant to catch' }
    [ordered]@{ Key = 'mac-unmanaged'; DisplayName = 'Laptop macOS Unmanaged'; OperatingSystem = 'MacOS'; OperatingSystemVersion = '14.5'; IsCompliant = 'FALSE'; IsManaged = 'FALSE'; AccountEnabled = 'TRUE'; RegisteredOwner = 'talvarez'; Tier = 'Core'; Purpose = 'Neither managed nor compliant, so any Windows-shaped assumption misses it entirely' }
    [ordered]@{ Key = 'ios-personal'; DisplayName = 'Handset iOS Personal'; OperatingSystem = 'IPhone'; OperatingSystemVersion = '17.5.1'; IsCompliant = 'FALSE'; IsManaged = 'FALSE'; AccountEnabled = 'TRUE'; RegisteredOwner = 'praghunathan'; Tier = 'Core'; Purpose = 'A mobile platform, where approved-client-app and app-protection controls behave differently' }
    [ordered]@{ Key = 'win-orphan'; DisplayName = 'Workstation Windows Orphaned'; OperatingSystem = 'Windows'; OperatingSystemVersion = '10.0.19045'; IsCompliant = 'FALSE'; IsManaged = 'TRUE'; AccountEnabled = 'TRUE'; RegisteredOwner = ''; Tier = 'Core'; Purpose = 'No registered owner at all, which is what a device left behind by a departed user looks like' }
    [ordered]@{ Key = 'win-disabled'; DisplayName = 'Workstation Windows Disabled'; OperatingSystem = 'Windows'; OperatingSystemVersion = '10.0.19045'; IsCompliant = 'FALSE'; IsManaged = 'TRUE'; AccountEnabled = 'FALSE'; RegisteredOwner = 'mbell'; Tier = 'Core'; Purpose = 'Disabled device belonging to a disabled user; still present in every unfiltered inventory' }
)

# --------------------------------------------------------------------------------------
# Bulk users, mapped from ADTestEnvironment
# --------------------------------------------------------------------------------------

$adUsers = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADUsers.csv') -Encoding UTF8)
Write-Verbose "Read $($adUsers.Count) AD users"

$coreKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreUsers.Key))
$adKeyByName = @{}
$bulkUsers = [System.Collections.Generic.List[object]]::new()

# The seeded environment is multinational on purpose, because usageLocation drives licence
# eligibility and a directory that is entirely US-based never exercises that.
$locations = @('US', 'US', 'US', 'GB', 'DE', 'ES', 'JP', 'CA', 'AU', 'IE')

foreach ($adUser in $adUsers) {
    $key = ConvertTo-Key $adUser.SamAccountName
    if (-not $key) { $key = ConvertTo-Key $adUser.Name }
    if (-not $key) { continue }

    # A generated row must never displace a hand-designed one carrying a deliberate edge case.
    if ($coreKeys.Contains($key)) { continue }
    if ($adKeyByName.ContainsKey($adUser.Name)) { continue }

    $adKeyByName[$adUser.Name] = $key
    $hash = Get-StableHash $key

    $bulkUsers.Add([ordered]@{
            Key                = $key
            GivenName          = $adUser.GivenName
            Surname            = $adUser.Surname
            DisplayName        = $adUser.Name
            Department         = $adUser.Department
            JobTitle           = $adUser.Title
            UsageLocation      = $locations[$hash % $locations.Count]
            AccountEnabled     = $(if ($adUser.Enabled -eq 'False') { 'FALSE' } else { 'TRUE' })
            Manager            = ''   # resolved in a second pass, once every key exists
            EmployeeId         = $adUser.EmployeeID
            EmployeeType       = $(if ($adUser.EmployeeType) { $adUser.EmployeeType } else { 'Employee' })
            MailDiffersFromUpn = 'FALSE'
            Tier               = 'Bulk'
            Purpose            = "Bulk directory volume, mapped from ADTestEnvironment ($($adUser.Department))"
        })
}

# Second pass for managers: AD names them by CN, and a manager can appear after their reports.
$adManagerByName = @{}
foreach ($adUser in $adUsers) { $adManagerByName[$adUser.Name] = ($adUser.Manager -replace '^CN=', '') }

foreach ($row in $bulkUsers) {
    $adName = ($adUsers | Where-Object { (ConvertTo-Key $_.SamAccountName) -eq $row.Key } | Select-Object -First 1).Name
    if (-not $adName) { continue }
    $managerName = $adManagerByName[$adName]
    if ($managerName -and $adKeyByName.ContainsKey($managerName)) {
        $row.Manager = $adKeyByName[$managerName]
    }
    elseif ($managerName) {
        # Their manager is one of the core users' territory, or was skipped as a duplicate.
        # Point them at the core chain rather than leaving an orphan, so the depth is real.
        $row.Manager = 'awhitfield'
    }
}

$allUsers = @($coreUsers) + @($bulkUsers)
Write-Verbose "Users: $($coreUsers.Count) core + $($bulkUsers.Count) bulk = $($allUsers.Count)"

# --------------------------------------------------------------------------------------
# Bulk groups, mapped from ADTestEnvironment, with real membership
# --------------------------------------------------------------------------------------

$adGroups = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADSecurityGroups.csv') -Encoding UTF8)
Write-Verbose "Read $($adGroups.Count) AD groups"

$coreGroupKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreGroups.Key))
$adGroupKeyByName = @{}
$bulkGroups = [System.Collections.Generic.List[object]]::new()

# Department groups get their department's people, so membership is non-trivial and the
# transitive expansion of a nested group is genuinely expensive.
$usersByDepartment = @{}
foreach ($row in $allUsers) {
    if (-not $row.Department) { continue }
    if (-not $usersByDepartment.ContainsKey($row.Department)) {
        $usersByDepartment[$row.Department] = [System.Collections.Generic.List[string]]::new()
    }
    $usersByDepartment[$row.Department].Add($row.Key)
}

foreach ($adGroup in $adGroups) {
    $key = ConvertTo-Key $adGroup.GroupName
    if (-not $key -or $coreGroupKeys.Contains($key) -or $adGroupKeyByName.ContainsKey($adGroup.GroupName)) { continue }
    $adGroupKeyByName[$adGroup.GroupName] = $key

    # A membership cap keeps the seed run bounded: every member is one Graph call, and a
    # forty-seven-person department would otherwise cost forty-seven of them for one group.
    $members = @()
    if ($usersByDepartment.ContainsKey($adGroup.Category)) {
        $members = @($usersByDepartment[$adGroup.Category] | Select-Object -First 12)
    }
    else {
        $hash = Get-StableHash $key
        $pool = @($allUsers.Key)
        $take = 3 + ($hash % 6)
        $members = @(0..($take - 1) | ForEach-Object { $pool[($hash + $_ * 7) % $pool.Count] } | Sort-Object -Unique)
    }

    $bulkGroups.Add([ordered]@{
            Key                = $key
            DisplayName        = $adGroup.GroupName
            GroupKind          = 'Security'
            MembershipType     = 'Assigned'
            MembershipRule     = ''
            Members            = ($members -join ';')
            MemberGroups       = ''   # resolved below, once every key exists
            IsAssignableToRole = 'FALSE'
            Tier               = 'Bulk'
            Purpose            = "Bulk directory volume, mapped from ADTestEnvironment ($($adGroup.Category))"
        })
}

# AD's MemberOfGroup gives real nesting. Reproducing it means the bulk groups form a genuine
# graph rather than a flat list, which is what makes transitive expansion worth measuring.
$bulkGroupByKey = @{}
foreach ($row in $bulkGroups) { $bulkGroupByKey[$row.Key] = $row }

foreach ($adGroup in $adGroups) {
    if (-not $adGroup.MemberOfGroup) { continue }
    $childKey = ConvertTo-Key $adGroup.GroupName
    $parentKey = ConvertTo-Key $adGroup.MemberOfGroup
    if (-not $bulkGroupByKey.ContainsKey($parentKey) -or -not $bulkGroupByKey.ContainsKey($childKey)) { continue }
    if ($parentKey -eq $childKey) { continue }

    $parent = $bulkGroupByKey[$parentKey]
    $existing = @($parent.MemberGroups -split ';' | Where-Object { $_ })
    if ($existing -notcontains $childKey) {
        $parent.MemberGroups = (@($existing) + $childKey) -join ';'
    }
}

$allGroups = @($coreGroups) + @($bulkGroups)
Write-Verbose "Groups: $($coreGroups.Count) core + $($bulkGroups.Count) bulk = $($allGroups.Count)"

# --------------------------------------------------------------------------------------
# Bulk devices, mapped from ADTestEnvironment
# --------------------------------------------------------------------------------------

$adDevices = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADDevices.csv') -Encoding UTF8)
Write-Verbose "Read $($adDevices.Count) AD devices"

$coreDeviceKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreDevices.Key))
$bulkDevices = [System.Collections.Generic.List[object]]::new()
$seenDeviceKeys = [System.Collections.Generic.HashSet[string]]::new()

$osProfiles = @(
    @{ Os = 'Windows'; Version = '10.0.26100' }
    @{ Os = 'Windows'; Version = '10.0.22631' }
    @{ Os = 'Windows'; Version = '10.0.19045' }
    @{ Os = 'MacOS'; Version = '14.5' }
    @{ Os = 'IPhone'; Version = '17.5.1' }
    @{ Os = 'Android'; Version = '14' }
)

foreach ($adDevice in $adDevices) {
    $key = ConvertTo-Key $adDevice.DeviceName
    if (-not $key -or $coreDeviceKeys.Contains($key) -or -not $seenDeviceKeys.Add($key)) { continue }

    $hash = Get-StableHash $key
    $osProfile = $osProfiles[$hash % $osProfiles.Count]

    # Derived from the hash so the mix is realistic and stable: most devices managed, a
    # meaningful minority not, and compliance failing on a slice of the managed ones.
    $isManaged = (($hash -shr 3) % 10) -lt 8
    $isCompliant = $isManaged -and ((($hash -shr 7) % 10) -lt 7)

    $owner = ''
    if ($adDevice.AssignedUser -and $adKeyByName.ContainsKey($adDevice.AssignedUser)) {
        $owner = $adKeyByName[$adDevice.AssignedUser]
    }

    $bulkDevices.Add([ordered]@{
            Key                    = $key
            DisplayName            = $adDevice.DeviceName
            OperatingSystem        = $osProfile.Os
            OperatingSystemVersion = $osProfile.Version
            IsCompliant            = $(if ($isCompliant) { 'TRUE' } else { 'FALSE' })
            IsManaged              = $(if ($isManaged) { 'TRUE' } else { 'FALSE' })
            AccountEnabled         = $(if ($adDevice.Enabled -eq 'False') { 'FALSE' } else { 'TRUE' })
            RegisteredOwner        = $owner
            Tier                   = 'Bulk'
            Purpose                = "Bulk device volume, mapped from ADTestEnvironment ($($adDevice.DeviceType))"
        })
}

$allDevices = @($coreDevices) + @($bulkDevices)
Write-Verbose "Devices: $($coreDevices.Count) core + $($bulkDevices.Count) bulk = $($allDevices.Count)"

# --------------------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------------------

$outputs = @(
    @{ Name = 'EntraUsers'; Rows = $allUsers }
    @{ Name = 'EntraGroups'; Rows = $allGroups }
    @{ Name = 'EntraDevices'; Rows = $allDevices }
)

foreach ($output in $outputs) {
    $path = Join-Path $OutputPath "$($output.Name).csv"
    if (-not $PSCmdlet.ShouldProcess($path, "Write $($output.Rows.Count) rows")) { continue }

    # UTF-8 with a BOM. Several rows carry accented names deliberately, and Windows
    # PowerShell reads a BOM-less file as ANSI and silently changes them.
    $objects = @($output.Rows | ForEach-Object { [PSCustomObject]$_ })
    $csv = ($objects | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($path, $csv + "`r`n", [System.Text.UTF8Encoding]::new($true))

    Write-Output ("{0,-16} {1,5} rows -> {2}" -f $output.Name, $output.Rows.Count, $path)
}
