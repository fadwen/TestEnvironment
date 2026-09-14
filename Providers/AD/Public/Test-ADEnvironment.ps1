function Test-ADEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded Active Directory domain matches the seed data
    .DESCRIPTION
        Reads the users, service accounts, computers and groups under the seed OU that carry the
        seed tag, the same way teardown finds them, and compares them with the seed files: every
        seeded account and name should be present, nothing the module owns should be there that
        the data does not describe, every user's display name should match the data by codepoint,
        and every membership the group rules define should hold.

        Group memberships are rules in the data rather than lists, so the expectation is computed
        the way the seed computes it - Resolve-ADTestGroupMember over the seeded directory - and
        then compared with what the group holds. Nesting from the MemberOfGroup column is checked
        the same way. Memberships are judged on what is missing only.

        Every lookup is scoped to the seed OU. When the seed OU is not there, nothing is seeded,
        and every check reports the whole of the data as missing.
    .PARAMETER SkipMembership
        Do not compare group memberships, which costs one Get-ADGroupMember per group with a rule
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-ADEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> (Test-ADEnvironment -Quiet).Checks | Where-Object { $_.Passed -eq $false }

        Lists only the checks that failed, with their missing and unexpected names.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipMembership,

        [Parameter()]
        [switch]$Quiet
    )

    $domain = Get-ADTestDomain
    $marker = Get-ADTestSeedMarker
    $dataPath = Get-ADTestDataPath
    $seedRoot = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -LiteralPath (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    $prefixed = { param($name) '{0}{1}' -f $marker.Prefix, $name }

    # Every search below is scoped to a child of the seed OU. A search base that does not exist
    # is an error to the AD cmdlets rather than an empty result, so the root is checked once.
    $rootExists = @(Get-ADOrganizationalUnit -Filter "Name -eq '$($script:ADTestRootName)'" -SearchBase $domain.DomainDN `
            -SearchScope OneLevel -ErrorAction Stop).Count -gt 0
    if (-not $rootExists) {
        Write-Warning "The seed OU $seedRoot does not exist; nothing is seeded."
    }
    $search = {
        param($Command, $Container, $Kind)
        if (-not $rootExists) { return @() }
        @(& $Command -Filter '*' -SearchBase "OU=$Container,$seedRoot" -Properties adminDescription, DisplayName -ErrorAction Stop |
                Select-ADTestOwnedObject -Kind $Kind)
    }

    # --- Users and service accounts --------------------------------------------------------
    $userRows = & $read 'ADUsers.csv'
    $users = & $search Get-ADUser 'Users' 'user'
    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { $_.SamAccountName }) `
                -Found @($users | ForEach-Object { [string]$_.SamAccountName }) -IgnoreCase))

    $userBySam = @{}
    foreach ($user in $users) { if ($user.SamAccountName) { $userBySam[([string]$user.SamAccountName).ToLowerInvariant()] = $user } }
    $compared = 0
    $mismatch = foreach ($row in $userRows) {
        $user = $userBySam[([string]$row.SamAccountName).ToLowerInvariant()]
        if (-not $user) { continue }
        $compared++
        if (-not [string]::Equals([string]$user.DisplayName, [string]$row.Name, [StringComparison]::Ordinal)) {
            "{0}: '{1}' should be '{2}'" -f $row.SamAccountName, $user.DisplayName, $row.Name
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User display names' -Compared $compared -Mismatch @($mismatch)))

    $serviceRows = & $read 'ADServiceAccounts.csv'
    $serviceAccounts = & $search Get-ADUser 'ServiceAccounts' 'service account'
    $checks.Add((New-TestEnvironmentCheck -Name 'Service accounts' `
                -Expected @($serviceRows | ForEach-Object { $_.SamAccountName }) `
                -Found @($serviceAccounts | ForEach-Object { [string]$_.SamAccountName }) -IgnoreCase))

    # --- Computers and groups --------------------------------------------------------------
    $deviceRows = & $read 'ADDevices.csv'
    $computers = & $search Get-ADComputer 'Devices' 'computer'
    $checks.Add((New-TestEnvironmentCheck -Name 'Computers' `
                -Expected @($deviceRows | ForEach-Object { & $prefixed $_.DeviceName }) `
                -Found @($computers | ForEach-Object { [string]$_.Name }) -IgnoreCase))

    $groupRows = & $read 'ADSecurityGroups.csv'
    $groups = & $search Get-ADGroup 'Groups' 'group'
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $prefixed $_.GroupName }) `
                -Found @($groups | ForEach-Object { [string]$_.Name }) -IgnoreCase))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership -and $rootExists) {
        $groupByName = @{}
        foreach ($group in $groups) { if ($group.Name) { $groupByName[([string]$group.Name).ToLowerInvariant()] = $group } }

        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $foundPairs = New-Object System.Collections.Generic.List[string]
        $read = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        $collect = {
            param($GroupName)
            if (-not $read.Add($GroupName)) { return }
            $group = $groupByName[$GroupName.ToLowerInvariant()]
            if (-not $group) { return }
            try {
                foreach ($member in @(Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction Stop)) {
                    if ($member.DistinguishedName) { $foundPairs.Add(('{0} <- {1}' -f $GroupName, [string]$member.DistinguishedName)) }
                }
            }
            catch {
                Write-Warning "Could not read the members of '$GroupName': $($_.Exception.Message). They are counted as missing."
            }
        }

        foreach ($row in $groupRows) {
            $groupName = & $prefixed $row.GroupName

            # The rule, evaluated over the seeded directory exactly as the seed evaluated it.
            $ruleMembers = @(Resolve-ADTestGroupMember -Rule $row -SeedRoot $seedRoot)
            foreach ($member in $ruleMembers) { $expectedPairs.Add(('{0} <- {1}' -f $groupName, [string]$member.DistinguishedName)) }
            if ($ruleMembers.Count -gt 0) { & $collect $groupName }

            # Nesting, from the child's row: the child group is a member of each parent it names.
            $child = $groupByName[$groupName.ToLowerInvariant()]
            foreach ($parentName in @([string]$row.MemberOfGroup -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                $parentGroupName = & $prefixed $parentName
                $childDn = if ($child) { [string]$child.DistinguishedName } else { "CN=$groupName,OU=Groups,$seedRoot" }
                $expectedPairs.Add(('{0} <- {1}' -f $parentGroupName, $childDn))
                & $collect $parentGroupName
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -IgnoreCase -MissingOnly))
    }

    return New-TestEnvironmentVerification -Provider 'AD' -Target $domain.DNSName -Check $checks.ToArray() -Quiet:$Quiet
}
