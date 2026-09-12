#Requires -Version 5.1

<#
    .SYNOPSIS
        Regenerates the Authentik user and group seed CSVs from the AD provider's, at AD parity

    .DESCRIPTION
        This is an authoring tool, not part of the module. It runs by hand when the seed data
        needs rebuilding, and the CSVs it writes are the committed artifact - the module never
        calls this at run time.

        The data has two halves and the distinction matters:

        - A hand-designed CORE, written into this file and preserved verbatim. These are the
          rows chosen to be awkward in a way that breaks scripts - the accented names, the
          disabled user who keeps memberships, the intern with no badge id, the contractor
          population outside the staff chain, the three-deep nesting chain. Volume does not
          make any of those more likely to be found, so they are never generated.
        - A generated BULK, mapped from the AD provider's people and groups. This is what makes
          pagination real, makes transitive membership expensive, and makes a report that works
          on ten users prove something about three hundred.

        Reusing AD's directory rather than inventing names is deliberate, and it is the same
        choice the Entra provider made: the same person then exists in the AD, Entra and
        Authentik labs, so anything matching identities across a hybrid boundary - by login,
        by display name, by badge - has three directories that genuinely correspond.

        Authentik has no manager field and no profile schema, so what AD carries as attributes
        becomes free-form lab attributes, and what AD carries as group membership becomes each
        user's group list. Membership is derived from what the AD data actually says: the
        department group whose name matches the person's department, the employment-type
        groups for their EmployeeType, the management-level groups their title implies, and
        the office group for their Office. Groups nothing in the data can decide - resource,
        application and device access - take a stable sample of the population, so none of
        them is empty and none of them is everybody.

        Everything here is deterministic. Attributes that need to vary (clearance level, risk
        score) are derived from a stable hash of the object's own key rather than from
        Get-Random, so regenerating produces byte-identical files and a diff shows real
        changes rather than churn. A test under Tests\Unit\Providers\Authentik regenerates the
        files into a temporary folder and fails if they differ from what is committed.

    .PARAMETER AdDataPath
        The AD provider's Data folder. Defaults to the one in this repository.

    .PARAMETER OutputPath
        Where to write the CSVs. Defaults to the Authentik provider's own Data folder.

    .PARAMETER WhatIf
        Reports what would be written without writing it.

    .EXAMPLE
        PS> .\New-AuthentikTestSeedData.ps1 -Verbose

        DESCRIPTION: Regenerates AuthentikUsers.csv and AuthentikGroups.csv at AD parity
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
Write-Verbose "Writing Authentik data to $OutputPath"

# A stable hash, so a rebuild produces identical files. Get-Random would reshuffle every
# derived attribute on every run and make the diff useless.
function Get-StableHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return [BitConverter]::ToUInt32($hash, 0)
}

# The same key derivation the Entra tool uses, so a person has the same login in both labs.
function ConvertTo-Key {
    param([string]$Text)
    $clean = ($Text -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

# --------------------------------------------------------------------------------------
# The hand-designed core. Preserved verbatim; never generated.
# --------------------------------------------------------------------------------------

$coreGroups = @(
    [ordered]@{ Name = 'All-Staff'; DisplayName = 'All Staff'; Parent = ''; Category = 'Organisation'; Description = 'Every internal employee'; Tier = 'Core'; Purpose = 'The root of the nesting chain and the broadest policy target' }
    [ordered]@{ Name = 'Dept-Engineering'; DisplayName = 'Department Engineering'; Parent = 'All-Staff'; Category = 'Department'; Description = 'Engineering department'; Tier = 'Core'; Purpose = 'Second level of the chain; a department with a team beneath it' }
    [ordered]@{ Name = 'Team-Platform'; DisplayName = 'Team Platform'; Parent = 'Dept-Engineering'; Category = 'Team'; Description = 'Platform engineering team'; Tier = 'Core'; Purpose = 'Third level; membership here must resolve transitively to All Staff' }
    [ordered]@{ Name = 'Dept-Sales'; DisplayName = 'Department Sales'; Parent = 'All-Staff'; Category = 'Department'; Description = 'Sales department'; Tier = 'Core'; Purpose = 'A sibling department with no children' }
    [ordered]@{ Name = 'Dept-Finance'; DisplayName = 'Department Finance'; Parent = 'All-Staff'; Category = 'Department'; Description = 'Finance department'; Tier = 'Core'; Purpose = 'Bound to the payroll application by policy' }
    [ordered]@{ Name = 'Contractors'; DisplayName = 'Contractors'; Parent = ''; Category = 'Population'; Description = 'External contractors'; Tier = 'Core'; Purpose = 'Deliberately outside the staff chain; the policies deny this group' }
    [ordered]@{ Name = 'Site-Zurich'; DisplayName = 'Zürich Site Access'; Parent = ''; Category = 'Site'; Description = 'Zürich office access'; Tier = 'Core'; Purpose = 'Non-ASCII display name that must survive the round trip' }
    [ordered]@{ Name = 'Empty-Hold'; DisplayName = 'Empty Hold'; Parent = ''; Category = 'Utility'; Description = 'A group with no members'; Tier = 'Core'; Purpose = 'A report has to handle zero members without special-casing' }
    [ordered]@{ Name = 'Lab-Admins'; DisplayName = 'Lab Admins'; Parent = ''; Category = 'Role'; Description = 'Lab administrators'; Tier = 'Core'; Purpose = 'Named like an admin group but never a superuser group' }
)

# José held decomposed: an e followed by U+0301 COMBINING ACUTE ACCENT, rather than the single
# precomposed U+00E9 that jnino carries. The two render identically, which is the point, so it
# is built from codepoints rather than typed - an editor that normalised this file on save
# would erase the case without changing a visible character.
$joseDecomposed = 'Jos' + [char]0x0065 + [char]0x0301

$coreUsers = @(
    [ordered]@{ Username = 'awhitfield'; Name = 'Ada Whitfield'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Chief Technology Officer'; Department = 'Engineering'; Manager = ''; Groups = 'All-Staff;Dept-Engineering;Lab-Admins'; LabBadgeId = 'B-1001'; LabClearanceLevel = 'Top Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '12'; LabEntitlements = 'vpn;wiki;expenses'; Tier = 'Core'; Purpose = 'Top of the manager chain' }
    [ordered]@{ Username = 'jnino'; Name = 'José Niño'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Platform Engineer'; Department = 'Engineering'; Manager = 'awhitfield'; Groups = 'All-Staff;Dept-Engineering;Team-Platform'; LabBadgeId = 'B-1002'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '35'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'Accented name; three-deep group membership' }
    [ordered]@{ Username = 'zmueller'; Name = 'Zoë Müller'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Platform Engineer'; Department = 'Engineering'; Manager = 'jnino'; Groups = 'All-Staff;Dept-Engineering;Team-Platform;Site-Zurich'; LabBadgeId = 'B-1003'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '28'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'Accented name; member of the accented group' }
    [ordered]@{ Username = 'mbell'; Name = 'Marcus Bell'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Sales Director'; Department = 'Sales'; Manager = 'awhitfield'; Groups = 'All-Staff;Dept-Sales'; LabBadgeId = 'B-1004'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '41'; LabEntitlements = 'expenses'; Tier = 'Core'; Purpose = 'A department with no children' }
    [ordered]@{ Username = 'praghunathan'; Name = 'Priya Raghunathan'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Finance Manager'; Department = 'Finance'; Manager = 'awhitfield'; Groups = 'All-Staff;Dept-Finance'; LabBadgeId = 'B-1005'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '19'; LabEntitlements = 'expenses;payroll'; Tier = 'Core'; Purpose = 'The only user the payroll policy admits' }
    [ordered]@{ Username = 'talvarez'; Name = 'Tomás Álvarez'; Type = 'internal'; IsActive = 'FALSE'; Title = 'Account Executive'; Department = 'Sales'; Manager = 'mbell'; Groups = 'All-Staff;Dept-Sales'; LabBadgeId = 'B-1006'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '67'; LabEntitlements = 'expenses'; Tier = 'Core'; Purpose = 'Disabled account that still holds memberships' }
    [ordered]@{ Username = 'hkobayashi'; Name = '小林 花'; Type = 'external'; IsActive = 'TRUE'; Title = 'Security Consultant'; Department = 'Contractors'; Manager = ''; Groups = 'Contractors'; LabBadgeId = 'B-2001'; LabClearanceLevel = 'Secret'; LabIsContractor = 'TRUE'; LabRiskScore = '55'; LabEntitlements = 'wiki'; Tier = 'Core'; Purpose = 'External type, contractor flag set; denied by policy; kanji name, which must not be folded back to Latin' }
    [ordered]@{ Username = 'ofitzgerald'; Name = 'Orla Fitzgerald'; Type = 'external'; IsActive = 'TRUE'; Title = 'UX Contractor'; Department = 'Contractors'; Manager = ''; Groups = 'Contractors'; LabBadgeId = 'B-2002'; LabClearanceLevel = 'Unclassified'; LabIsContractor = 'TRUE'; LabRiskScore = '73'; LabEntitlements = ''; Tier = 'Core'; Purpose = 'Contractor with no entitlements at all' }
    [ordered]@{ Username = 'nsorensen'; Name = 'Nadia Sørensen'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Intern'; Department = 'Engineering'; Manager = 'jnino'; Groups = 'All-Staff;Dept-Engineering'; LabBadgeId = ''; LabClearanceLevel = 'Unclassified'; LabIsContractor = 'FALSE'; LabRiskScore = '8'; LabEntitlements = ''; Tier = 'Core'; Purpose = 'No badge id; a report must cope with a missing attribute' }
    [ordered]@{ Username = 'svc-reporting'; Name = 'Reporting Service'; Type = 'service_account'; IsActive = 'TRUE'; Title = ''; Department = ''; Manager = ''; Groups = ''; LabBadgeId = ''; LabClearanceLevel = ''; LabIsContractor = 'FALSE'; LabRiskScore = '0'; LabEntitlements = ''; Tier = 'Core'; Purpose = 'A service account among the humans, which must never be mistaken for the automation account' }

    # The script cohort, matching the same nine keys in the Entra and FreeIPA cores and the
    # same nine people in the AD directory. The username stays ASCII because it is what the
    # API path and the seed prefix are built from; the writing system lives in the name.
    [ordered]@{ Username = 'jjiang'; Name = '姜　俊誉'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Site Reliability Engineer'; Department = 'Engineering'; Manager = 'jnino'; Groups = 'All-Staff;Dept-Engineering;Team-Platform'; LabBadgeId = 'B-1021'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '22'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'Han name, family name first, separated by an ideographic space rather than U+0020' }
    [ordered]@{ Username = 'tyoshida'; Name = '𠮷田 太郎'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Build Engineer'; Department = 'Engineering'; Manager = 'jnino'; Groups = 'All-Staff;Dept-Engineering'; LabBadgeId = 'B-1022'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '18'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'A surname above the basic plane, so one character occupies two UTF-16 units' }
    [ordered]@{ Username = 'dvolkov'; Name = 'Дмитрий Волков'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Infrastructure Engineer'; Department = 'Engineering'; Manager = 'awhitfield'; Groups = 'All-Staff;Dept-Engineering'; LabBadgeId = 'B-1023'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '31'; LabEntitlements = 'vpn'; Tier = 'Core'; Purpose = 'Cyrillic homoglyphs, which a duplicate check made by eye cannot tell from Latin' }
    [ordered]@{ Username = 'gpapadopoulos'; Name = 'Γιώργος Παπαδόπουλος'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Financial Analyst'; Department = 'Finance'; Manager = 'awhitfield'; Groups = 'All-Staff'; LabBadgeId = 'B-1024'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '15'; LabEntitlements = 'expenses'; Tier = 'Core'; Purpose = 'In no department group, because praghunathan is meant to be the only member the payroll rule admits. Greek final sigma, so upper-casing and lower-casing the name does not return the name' }
    [ordered]@{ Username = 'malahmad'; Name = 'محمد الأحمد'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Network Engineer'; Department = 'Engineering'; Manager = 'awhitfield'; Groups = 'All-Staff;Dept-Engineering'; LabBadgeId = 'B-1025'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '27'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'Right-to-left text, stored in one order and displayed in another once Latin joins it' }
    [ordered]@{ Username = 'jmarchetti'; Name = "$joseDecomposed Marchetti"; Type = 'internal'; IsActive = 'TRUE'; Title = 'Campaign Manager'; Department = 'Marketing'; Manager = 'mbell'; Groups = 'All-Staff'; LabBadgeId = 'B-1026'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '44'; LabEntitlements = 'wiki'; Tier = 'Core'; Purpose = 'The same José as jnino to the eye, stored decomposed, so the two are different strings' }
    [ordered]@{ Username = 'iisik'; Name = 'Irmak Işık'; Type = 'internal'; IsActive = 'TRUE'; Title = 'HR Advisor'; Department = 'Human Resources'; Manager = 'awhitfield'; Groups = 'All-Staff'; LabBadgeId = 'B-1027'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '11'; LabEntitlements = 'wiki'; Tier = 'Core'; Purpose = 'Turkish dotted and dotless i, which lower-case differently under a Turkish culture' }
    [ordered]@{ Username = 'jweiss'; Name = 'Jürgen Weiß'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Account Executive'; Department = 'Sales'; Manager = 'mbell'; Groups = 'All-Staff;Dept-Sales'; LabBadgeId = 'B-1028'; LabClearanceLevel = 'Confidential'; LabIsContractor = 'FALSE'; LabRiskScore = '38'; LabEntitlements = 'expenses'; Tier = 'Core'; Purpose = 'An eszett, which upper-cases into two characters and makes the name longer' }
    [ordered]@{ Username = 'schaudhary'; Name = 'सुनीता चौधरी'; Type = 'internal'; IsActive = 'TRUE'; Title = 'Data Engineer'; Department = 'Engineering'; Manager = 'jnino'; Groups = 'All-Staff;Dept-Engineering;Team-Platform'; LabBadgeId = 'B-1029'; LabClearanceLevel = 'Secret'; LabIsContractor = 'FALSE'; LabRiskScore = '9'; LabEntitlements = 'vpn;wiki'; Tier = 'Core'; Purpose = 'Devanagari combining vowel signs, so character count and visible marks are different numbers' }
)

# --------------------------------------------------------------------------------------
# Bulk groups, mapped from the AD provider, with AD's own nesting
# --------------------------------------------------------------------------------------

$adGroups = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADSecurityGroups.csv') -Encoding UTF8)
Write-Verbose "Read $($adGroups.Count) AD groups"

$coreGroupKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreGroups.Name))
$coreGroupNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($coreGroups.DisplayName))
$groupKeyByAdName = @{}
$bulkGroups = [System.Collections.Generic.List[object]]::new()

foreach ($adGroup in $adGroups) {
    $key = ConvertTo-Key $adGroup.GroupName
    # A generated row must never displace a hand-designed one, and Authentik group names are
    # unique, so a bulk group whose display name a core group already uses is dropped.
    if (-not $key -or $coreGroupKeys.Contains($key) -or $coreGroupNames.Contains($adGroup.GroupName)) { continue }
    if ($groupKeyByAdName.ContainsKey($adGroup.GroupName)) { continue }
    $groupKeyByAdName[$adGroup.GroupName] = $key

    $bulkGroups.Add([ordered]@{
            Name        = $key
            DisplayName = $adGroup.GroupName
            Parent      = ''   # resolved below, once every key exists
            Category    = $adGroup.Category
            Description = $adGroup.Description
            Tier        = 'Bulk'
            Purpose     = "Bulk directory volume, mapped from the AD provider ($($adGroup.Category))"
        })
}

# AD's MemberOfGroup gives real nesting, and a group can name more than one parent. Authentik
# groups take a list of parents, so the graph is reproduced as it is rather than flattened to
# a tree, which is what makes transitive expansion worth measuring.
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
# Bulk users, mapped from the AD provider
# --------------------------------------------------------------------------------------

$adUsers = @(Import-Csv -LiteralPath (Join-Path $AdDataPath 'ADUsers.csv') -Encoding UTF8)
Write-Verbose "Read $($adUsers.Count) AD users"

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
    'Seattle - Main'        = 'seattlemainoffice'
    'Seattle - Engineering' = 'seattleengineeringoffice'
    'Seattle - Finance'     = 'seattlefinanceoffice'
    'Houston - Sales'       = 'houstonoffice'
    'New York - Strategy'   = 'newyorkoffice'
    'New York - Northeast'  = 'newyorkoffice'
    'Chicago - Central'     = 'chicagooffice'
    'Atlanta - Southeast'   = 'atlantaoffice'
    'Boston - Northeast'    = 'bostonoffice'
    'Los Angeles - West'    = 'losangelesoffice'
    'Richmond - East'       = 'richmondoffice'
    'London - International' = 'londonoffice'
    'Remote - Field Sales'  = 'remoteworkers'
}

$clearances = @('Unclassified', 'Unclassified', 'Confidential', 'Confidential', 'Confidential', 'Secret')

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
    $hash = Get-StableHash $key
    $isContractor = $adUser.EmployeeType -eq 'Contractor'
    $isIntern = $adUser.EmployeeType -eq 'Intern'
    $title = [string]$adUser.Title

    # The population groups come from employment type. Contractors sit outside the staff
    # chain in both tiers: the core Contractors group is what the seeded policies deny, and
    # AD's own contractor groups nest beneath it in spirit if not in structure.
    if ($isContractor) {
        & $addMembership $key 'Contractors'
        & $addMembership $key 'allcontractors'
        & $addMembership $key 'contractworkers'
    }
    elseif ($isIntern) {
        & $addMembership $key 'All-Staff'
        & $addMembership $key 'allinterns'
        & $addMembership $key 'internemployees'
    }
    else {
        & $addMembership $key 'All-Staff'
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

    $bulkUsers.Add([ordered]@{
            Username          = $key
            Name              = $adUser.Name
            Type              = $(if ($isContractor) { 'external' } else { 'internal' })
            IsActive          = $(if ($adUser.Enabled -eq 'False') { 'FALSE' } else { 'TRUE' })
            Title             = $title
            Department        = $adUser.Department
            Manager           = ''   # resolved in a second pass, once every key exists
            Groups            = ''   # resolved after the sampled groups are filled
            LabBadgeId        = $(if ($adUser.EmployeeID -match '(\d+)$') { 'B-{0}' -f (3000 + [int]$Matches[1]) } else { '' })
            LabClearanceLevel = $clearances[$hash % $clearances.Count]
            LabIsContractor   = $(if ($isContractor) { 'TRUE' } else { 'FALSE' })
            LabRiskScore      = [string](($hash -shr 5) % 100)
            LabEntitlements   = ''   # derived from membership below
            Tier              = 'Bulk'
            Purpose           = "Bulk directory volume, mapped from the AD provider ($($adUser.Department))"
        })
}

# The groups nothing in the data can decide take a stable sample of the population, so a
# report meets groups of every size and none of them is empty by accident. Empty-Hold stays
# empty on purpose.
$assigned = [System.Collections.Generic.HashSet[string]]::new()
foreach ($list in $membership.Values) { foreach ($g in $list) { $null = $assigned.Add($g) } }
$pool = @($bulkUsers | Where-Object { $_.LabIsContractor -ne 'TRUE' } | ForEach-Object { $_.Username })

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

# Entitlements follow from what the person can reach, so they agree with the groups.
$entitlementByGroup = @{
    'vpnusers'            = 'vpn'
    'engineering'         = 'wiki'
    'engineeringoperations' = 'wiki'
    'developmenttools'    = 'wiki'
    'expensesystemaccess' = 'expenses'
    'payrollsystemaccess' = 'payroll'
}

foreach ($row in $bulkUsers) {
    $managerName = $adManagerByName[$row.Name]
    if ($managerName -and $userKeyByAdName.ContainsKey($managerName)) { $row.Manager = $userKeyByAdName[$managerName] }
    elseif ($managerName) { $row.Manager = 'awhitfield' }

    $groups = @()
    if ($membership.ContainsKey($row.Username)) { $groups = @($membership[$row.Username]) }
    $row.Groups = ($groups -join ';')

    $entitlements = foreach ($g in $groups) { if ($entitlementByGroup.ContainsKey($g)) { $entitlementByGroup[$g] } }
    $row.LabEntitlements = (@($entitlements | Select-Object -Unique) -join ';')
}

$allUsers = @($coreUsers) + @($bulkUsers)
Write-Verbose "Users: $($coreUsers.Count) core + $($bulkUsers.Count) bulk = $($allUsers.Count)"

# --------------------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------------------

$outputs = @(
    @{ Name = 'AuthentikGroups'; Rows = $allGroups }
    @{ Name = 'AuthentikUsers'; Rows = $allUsers }
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
