function Test-EntraEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded Entra tenant matches the seed data
    .DESCRIPTION
        Reads the users, groups, devices and applications the module owns in the connected tenant,
        the same way teardown finds them, and compares them with the seed files: every seeded UPN,
        group, device and application name should be present, nothing the module owns should be
        there that the data does not describe, every user's display name should match the data by
        codepoint, and every member a group row lists should be in that group.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name are
        equal to -eq and different on the wire; a name that came back mangled is the fault this
        exists to catch. UPNs are compared case-insensitively because the directory folds them.

        Guests are counted rather than named, because an invited guest's UPN is minted by Entra.
        Memberships are judged on what is missing only: a dynamic group owns its own membership.

        Service principals, named locations, Conditional Access policies, administrative units,
        authentication strengths, directory roles and role eligibilities are counted and reported
        without a verdict: how many of them a seed can create depends on the tenant's licence, and
        a tenant without P2 is not a fault of the seed.
    .PARAMETER SkipMembership
        Do not read group memberships, which costs one batched request per seeded group
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-EntraEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> (Test-EntraEnvironment -Quiet).Checks | Where-Object { $_.Passed -eq $false }

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

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection
    $checks = New-Object System.Collections.Generic.List[object]

    $prefixed = { param($name) '{0}{1}' -f $marker.Prefix, $name }
    $upnOf = { param($key) '{0}{1}@{2}' -f $marker.Prefix, $key, $marker.UpnSuffix }

    # --- Users -----------------------------------------------------------------------------
    $userRows = @(Get-EntraSeedData -Name EntraUsers)
    $guestRows = @(Get-EntraSeedData -Name EntraGuestUsers)
    $allUsers = @(Get-EntraSeededObject -Type Users -Connection $connection)
    $members = @($allUsers | Where-Object { $_.userType -ne 'Guest' })
    $guests = @($allUsers | Where-Object { $_.userType -eq 'Guest' })

    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { & $upnOf $_.Key }) `
                -Found @($members | ForEach-Object { [string]$_.userPrincipalName }) -IgnoreCase))

    $userByUpn = @{}
    foreach ($user in $members) {
        if ($user.userPrincipalName) { $userByUpn[([string]$user.userPrincipalName).ToLowerInvariant()] = $user }
    }
    $compared = 0
    $mismatch = foreach ($row in $userRows) {
        $user = $userByUpn[(& $upnOf $row.Key).ToLowerInvariant()]
        if (-not $user) { continue }
        $compared++
        if (-not [string]::Equals([string]$user.displayName, [string]$row.DisplayName, [StringComparison]::Ordinal)) {
            "{0}: '{1}' should be '{2}'" -f $row.Key, $user.displayName, $row.DisplayName
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User display names' -Compared $compared -Mismatch @($mismatch)))
    $checks.Add((New-TestEnvironmentCheck -Name 'Guests' -FoundCount $guests.Count -ExpectedCount $guestRows.Count))

    # --- Groups, devices, applications -----------------------------------------------------
    $groupRows = @(Get-EntraSeedData -Name EntraGroups)
    $groups = @(Get-EntraSeededObject -Type Groups -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $prefixed $_.DisplayName }) `
                -Found @($groups | ForEach-Object { [string]$_.displayName })))

    $deviceRows = @(Get-EntraSeedData -Name EntraDevices)
    $devices = @(Get-EntraSeededObject -Type Devices -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Devices' `
                -Expected @($deviceRows | ForEach-Object { & $prefixed $_.DisplayName }) `
                -Found @($devices | ForEach-Object { [string]$_.displayName })))

    $applicationRows = @(Get-EntraSeedData -Name EntraApplications)
    $expectedApplications = @($applicationRows | ForEach-Object { & $prefixed $_.DisplayName })
    # The directory extensions live on a schema application of their own, which the extension
    # step creates and no row names.
    if (@(Get-EntraSeedData -Name EntraDirectoryExtensions).Count -gt 0) { $expectedApplications += (& $prefixed 'Schema') }
    $applications = @(Get-EntraSeededObject -Type Applications -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Applications' `
                -Expected $expectedApplications `
                -Found @($applications | ForEach-Object { [string]$_.displayName })))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership) {
        # A group row names its members by user key and its member groups by group key; the
        # directory answers with UPNs and display names.
        $groupNameByKey = @{}
        foreach ($row in $groupRows) { $groupNameByKey[$row.Key] = & $prefixed $row.DisplayName }
        $groupByName = @{}
        foreach ($group in $groups) { if ($group.displayName) { $groupByName[[string]$group.displayName] = $group } }

        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $requests = New-Object System.Collections.Generic.List[object]
        foreach ($row in $groupRows) {
            if ($row.MembershipType -eq 'Dynamic') { continue }
            $memberKeys = @($row.Members -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
            $memberGroupKeys = @($row.MemberGroups -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
            if ($memberKeys.Count + $memberGroupKeys.Count -eq 0) { continue }

            $groupName = & $prefixed $row.DisplayName
            foreach ($key in $memberKeys) { $expectedPairs.Add(('{0} <- {1}' -f $groupName, (& $upnOf $key))) }
            foreach ($key in $memberGroupKeys) {
                $memberGroupName = if ($groupNameByKey.ContainsKey($key)) { $groupNameByKey[$key] } else { & $prefixed $key }
                $expectedPairs.Add(('{0} <- {1}' -f $groupName, $memberGroupName))
            }

            $group = $groupByName[$groupName]
            if ($group) {
                $requests.Add([PSCustomObject]@{
                        Reference = $groupName
                        Method    = 'GET'
                        Url       = "/groups/$($group.id)/members?`$select=id,displayName,userPrincipalName&`$top=999"
                    })
            }
        }

        $foundPairs = New-Object System.Collections.Generic.List[string]
        if ($requests.Count -gt 0) {
            foreach ($result in (Invoke-EntraBatch -Request $requests.ToArray() -Connection $connection -Activity 'Reading memberships')) {
                if (-not $result.Success) {
                    Write-Warning "Could not read the members of '$($result.Reference)' (HTTP $($result.Status)). They are counted as missing."
                    continue
                }
                foreach ($member in @($result.Body.value)) {
                    if ($null -eq $member) { continue }
                    $identifier = if ($member.userPrincipalName) { [string]$member.userPrincipalName } else { [string]$member.displayName }
                    if ($identifier) { $foundPairs.Add(('{0} <- {1}' -f $result.Reference, $identifier)) }
                }
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -IgnoreCase -MissingOnly))
    }

    # --- Everything the licence decides, counted -------------------------------------------
    $capability = $connection.Capabilities
    foreach ($type in 'ServicePrincipals', 'NamedLocations', 'ConditionalAccessPolicies', 'AdministrativeUnits',
        'AuthenticationStrengths', 'DirectoryRoles', 'RoleEligibilities') {
        if ($type -eq 'RoleEligibilities' -and $capability -and $capability.Known -and -not $capability.EntraP2) {
            # Without P2 there can be none, and the read would be refused.
            $checks.Add((New-TestEnvironmentCheck -Name $type -FoundCount 0))
            continue
        }
        try {
            $count = @(Get-EntraSeededObject -Type $type -Connection $connection).Count
            $checks.Add((New-TestEnvironmentCheck -Name $type -FoundCount $count))
        }
        catch {
            Write-Warning "Could not count the seeded $type`: $($_.Exception.Message)"
        }
    }

    return New-TestEnvironmentVerification -Provider 'Entra' -Target $connection.TenantId -Check $checks.ToArray() -Quiet:$Quiet
}
