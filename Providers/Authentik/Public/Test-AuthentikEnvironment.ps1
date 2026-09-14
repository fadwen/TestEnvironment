function Test-AuthentikEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded Authentik instance matches the seed data
    .DESCRIPTION
        Reads the users, groups and applications the module owns in the connected instance, the
        same way teardown finds them, and compares them with the seed files: every seeded username,
        group name and application name should be present, nothing the module owns should be there
        that the data does not describe, every user's name should match the data by codepoint, and
        every group a user row lists should hold that user.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name are
        equal to -eq and different on the wire; a name that came back mangled is the fault this
        exists to catch.

        Every other seeded type - providers, entitlements, scope mappings, roles, outposts,
        certificates, flows, stages, policies, notification rules and transports, tokens and
        invitations - is counted and reported without a verdict, because its rows do not map one
        to one onto objects.
    .PARAMETER SkipMembership
        Do not compare group memberships
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-AuthentikEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> (Test-AuthentikEnvironment -Quiet).Checks | Where-Object { $_.Passed -eq $false }

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

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection
    $dataPath = Get-AuthentikDataPath
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    $prefixed = { param($name) '{0}{1}' -f $marker.Prefix, $name }

    # --- Users -----------------------------------------------------------------------------
    $userRows = & $read 'AuthentikUsers.csv'
    $users = @(Get-AuthentikSeededObject -Type Users -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { $_.Username }) `
                -Found @($users | ForEach-Object { [string]$_.username })))

    $userByName = @{}
    foreach ($user in $users) { if ($user.username) { $userByName[[string]$user.username] = $user } }
    $compared = 0
    $mismatch = foreach ($row in $userRows) {
        $user = $userByName[$row.Username]
        if (-not $user) { continue }
        $compared++
        if (-not [string]::Equals([string]$user.name, [string]$row.Name, [StringComparison]::Ordinal)) {
            "{0}: '{1}' should be '{2}'" -f $row.Username, $user.name, $row.Name
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User names' -Compared $compared -Mismatch @($mismatch)))

    # --- Groups and applications -----------------------------------------------------------
    $groupRows = & $read 'AuthentikGroups.csv'
    $groups = @(Get-AuthentikSeededObject -Type Groups -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $prefixed $_.DisplayName }) `
                -Found @($groups | ForEach-Object { [string]$_.name })))

    $applicationRows = & $read 'AuthentikApplications.csv'
    $applications = @(Get-AuthentikSeededObject -Type Applications -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Applications' `
                -Expected @($applicationRows | ForEach-Object { & $prefixed $_.Name }) `
                -Found @($applications | ForEach-Object { [string]$_.name })))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership) {
        # A user row names its groups by their row key; the instance names them by their prefixed
        # display name and holds them on the user as primary keys.
        $groupNameByKey = @{}
        foreach ($row in $groupRows) { $groupNameByKey[$row.Name] = & $prefixed $row.DisplayName }
        $groupNameByPk = @{}
        foreach ($group in $groups) { $groupNameByPk[[string]$group.pk] = [string]$group.name }

        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $foundPairs = New-Object System.Collections.Generic.List[string]
        foreach ($row in $userRows) {
            foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) {
                $groupName = if ($groupNameByKey.ContainsKey($key)) { $groupNameByKey[$key] } else { & $prefixed $key }
                $expectedPairs.Add(('{0} <- {1}' -f $groupName, $row.Username))
            }
        }
        foreach ($user in $users) {
            foreach ($pk in @($user.groups)) {
                $groupName = $groupNameByPk[[string]$pk]
                if ($groupName) { $foundPairs.Add(('{0} <- {1}' -f $groupName, [string]$user.username)) }
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -MissingOnly))
    }

    # --- Everything else, counted ----------------------------------------------------------
    foreach ($type in 'Providers', 'Entitlements', 'ScopeMappings', 'Roles', 'Outposts', 'Certificates', 'Flows', 'Stages',
        'Policies', 'NotificationRules', 'NotificationTransports', 'Tokens', 'Invitations') {
        try {
            $count = @(Get-AuthentikSeededObject -Type $type -Connection $connection).Count
            $checks.Add((New-TestEnvironmentCheck -Name $type -FoundCount $count))
        }
        catch {
            Write-Warning "Could not count the seeded $type`: $($_.Exception.Message)"
        }
    }

    return New-TestEnvironmentVerification -Provider 'Authentik' -Target $connection.BaseUrl -Check $checks.ToArray() -Quiet:$Quiet
}
