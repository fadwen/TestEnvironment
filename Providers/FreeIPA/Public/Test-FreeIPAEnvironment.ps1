function Test-FreeIPAEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded FreeIPA realm matches the seed data
    .DESCRIPTION
        Reads the users, groups and hosts the module owns in the connected realm, the same way
        teardown finds them, and compares them with the seed files: every seeded user, staged user,
        preserved user, group and host should be present, nothing the module owns should be there
        that the data does not describe, every user's display name should match the data by
        codepoint, and every group a user row lists and every hostgroup a host row lists should
        hold its member.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name are
        equal to -eq and different on the wire; a name that came back mangled is the fault this
        exists to catch. Logins and host names are compared case-insensitively because the realm
        folds them.

        Memberships are judged on what is missing only: an automember rule adds members the data
        never lists, and that is not a fault.

        Every other seeded type is counted and reported without a verdict, because its rows do not
        map one to one onto objects.
    .PARAMETER SkipMembership
        Do not compare group and hostgroup memberships
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-FreeIPAEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> (Test-FreeIPAEnvironment -Quiet).Checks | Where-Object { $_.Passed -eq $false }

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

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $dataPath = Get-FreeIPADataPath
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    # FreeIPA returns every attribute as a list, even a single-valued one.
    $first = {
        param($value)
        if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } }
        elseif ($null -eq $value) { '' }
        else { [string]$value }
    }
    $nameOf = { param($key) Resolve-FreeIPASeedName -Key $key -Marker $marker -Connection $connection }
    $hostOf = { param($key) Resolve-FreeIPASeedName -Key $key -Kind Host -Marker $marker -Connection $connection }

    # --- Users, by lifecycle ---------------------------------------------------------------
    # A user's uid is its row's username as written, with no prefix: the seed prefixes the
    # names it invents - groups, hosts, rules - and leaves logins alone, the same as Authentik.
    $userRows = & $read 'FreeIPAUsers.csv'
    $activeRows = @($userRows | Where-Object { $_.Lifecycle -notin 'Staged', 'Preserved' })
    $stagedRows = @($userRows | Where-Object { $_.Lifecycle -eq 'Staged' })
    $preservedRows = @($userRows | Where-Object { $_.Lifecycle -eq 'Preserved' })

    $users = @(Get-FreeIPASeededObject -Type Users -Detail -Connection $connection)
    $staged = @(Get-FreeIPASeededObject -Type StagedUsers -Connection $connection)
    $preserved = @(Get-FreeIPASeededObject -Type PreservedUsers -Connection $connection)

    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($activeRows | ForEach-Object { $_.Username }) `
                -Found @($users | ForEach-Object { & $first $_.uid }) -IgnoreCase))
    $checks.Add((New-TestEnvironmentCheck -Name 'Staged users' `
                -Expected @($stagedRows | ForEach-Object { $_.Username }) `
                -Found @($staged | ForEach-Object { & $first $_.uid }) -IgnoreCase))
    $checks.Add((New-TestEnvironmentCheck -Name 'Preserved users' `
                -Expected @($preservedRows | ForEach-Object { $_.Username }) `
                -Found @($preserved | ForEach-Object { & $first $_.uid }) -IgnoreCase))

    $userByUid = @{}
    foreach ($user in $users) {
        $uid = & $first $user.uid
        if ($uid) { $userByUid[$uid.ToLowerInvariant()] = $user }
    }
    $compared = 0
    $mismatch = foreach ($row in $activeRows) {
        $user = $userByUid[([string]$row.Username).ToLowerInvariant()]
        if (-not $user) { continue }
        $compared++
        $actual = & $first $user.displayname
        if (-not [string]::Equals($actual, [string]$row.DisplayName, [StringComparison]::Ordinal)) {
            "{0}: '{1}' should be '{2}'" -f $row.Username, $actual, $row.DisplayName
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User display names' -Compared $compared -Mismatch @($mismatch)))

    # --- Groups and hosts ------------------------------------------------------------------
    $groupRows = & $read 'FreeIPAGroups.csv'
    $groups = @(Get-FreeIPASeededObject -Type Groups -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $nameOf $_.Name }) `
                -Found @($groups | ForEach-Object { & $first $_.cn }) -IgnoreCase))

    $hostRows = & $read 'FreeIPAHosts.csv'
    $hosts = @(Get-FreeIPASeededObject -Type Hosts -Detail -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Hosts' `
                -Expected @($hostRows | ForEach-Object { & $hostOf $_.Name }) `
                -Found @($hosts | ForEach-Object { & $first $_.fqdn }) -IgnoreCase))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership) {
        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $foundPairs = New-Object System.Collections.Generic.List[string]
        foreach ($row in $activeRows) {
            $uid = [string]$row.Username
            foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) {
                $expectedPairs.Add(('{0} <- {1}' -f (& $nameOf $key), $uid))
            }
        }
        foreach ($user in $users) {
            $uid = & $first $user.uid
            foreach ($groupName in @($user.memberof_group)) {
                if ($groupName) { $foundPairs.Add(('{0} <- {1}' -f [string]$groupName, $uid)) }
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -IgnoreCase -MissingOnly))

        $expectedHostPairs = New-Object System.Collections.Generic.List[string]
        $foundHostPairs = New-Object System.Collections.Generic.List[string]
        foreach ($row in $hostRows) {
            $fqdn = & $hostOf $row.Name
            foreach ($key in @($row.Hostgroups -split ';' | Where-Object { $_ })) {
                $expectedHostPairs.Add(('{0} <- {1}' -f (& $nameOf $key), $fqdn))
            }
        }
        foreach ($seededHost in $hosts) {
            $fqdn = & $first $seededHost.fqdn
            foreach ($hostgroupName in @($seededHost.memberof_hostgroup)) {
                if ($hostgroupName) { $foundHostPairs.Add(('{0} <- {1}' -f [string]$hostgroupName, $fqdn)) }
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Hostgroup memberships' -Expected $expectedHostPairs -Found $foundHostPairs -IgnoreCase -MissingOnly))
    }

    # --- Everything else, counted ----------------------------------------------------------
    foreach ($type in 'Hostgroups', 'Netgroups', 'HbacServices', 'HbacServiceGroups', 'HbacRules', 'SudoCommands',
        'SudoCommandGroups', 'SudoRules', 'Permissions', 'Privileges', 'Roles', 'PasswordPolicies', 'Services',
        'ServiceDelegationRules', 'ServiceDelegationTargets', 'IdViews', 'OtpTokens', 'AutomemberRules',
        'AutomountLocations', 'SelinuxUserMaps', 'CertMapRules', 'CaAcls', 'Certificates', 'DnsZones', 'DnsRecords',
        'RadiusProxies', 'IdentityProviders') {
        try {
            $count = @(Get-FreeIPASeededObject -Type $type -Connection $connection).Count
            $checks.Add((New-TestEnvironmentCheck -Name $type -FoundCount $count))
        }
        catch {
            Write-Warning "Could not count the seeded $type`: $($_.Exception.Message)"
        }
    }

    return New-TestEnvironmentVerification -Provider 'FreeIPA' -Target $connection.BaseUrl -Check $checks.ToArray() -Quiet:$Quiet
}
