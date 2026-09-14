function Test-PingOneEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded PingOne environment matches the seed data
    .DESCRIPTION
        Reads the populations, users, groups, applications, resources and attributes the module
        owns in the connected environment, the same way teardown finds them, and compares them with
        the seed files: every seeded name should be present, nothing the module owns should be
        there that the data does not describe, every user's given and family name should match the
        data by codepoint, and every group a user row lists should hold that user.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name are
        equal to -eq and different on the wire; a name that came back mangled is the fault this
        exists to catch, and it is the fault the PingOne provider once shipped. Usernames are
        compared case-insensitively because PingOne folds them.

        Memberships are read one user at a time, for the users the data puts in a group, and are
        judged on what is missing only: a dynamic group's filter and a nested group add members
        the data never lists, and that is not a fault.
    .PARAMETER SkipMembership
        Do not read group memberships, which costs one call per seeded user that has any
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-PingOneEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> Test-PingOneEnvironment -SkipMembership -Quiet | Select-Object -ExpandProperty Checks

        The object checks alone, as objects.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipMembership,

        [Parameter()]
        [switch]$Quiet
    )

    $connection = Get-PingOneConnection
    $dataPath = Get-PingOneDataPath
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -LiteralPath (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    $displayOf = { param($key) Resolve-PingOneSeedName -Key $key -Kind DisplayName -Connection $connection }
    $usernameOf = { param($key) Resolve-PingOneSeedName -Key $key -Kind Username -Connection $connection }

    # --- Populations -----------------------------------------------------------------------
    $populationRows = & $read 'PingOnePopulations.csv'
    $populations = @(Get-PingOneSeededObject -Type Populations -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Populations' `
                -Expected @($populationRows | ForEach-Object { & $displayOf $_.Name }) `
                -Found @($populations | ForEach-Object { [string]$_.name })))

    # --- Users -----------------------------------------------------------------------------
    $userRows = & $read 'PingOneUsers.csv'
    $users = @(Get-PingOneSeededObject -Type Users -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { & $usernameOf $_.Key }) `
                -Found @($users | ForEach-Object { [string]$_.username }) -IgnoreCase))

    $userByName = @{}
    foreach ($user in $users) { if ($user.username) { $userByName[([string]$user.username).ToLowerInvariant()] = $user } }
    $compared = 0
    $mismatch = foreach ($row in $userRows) {
        $user = $userByName[(& $usernameOf $row.Key).ToLowerInvariant()]
        if (-not $user) { continue }
        $compared++
        $given = [string]$user.name.given
        $family = [string]$user.name.family
        if ($row.GivenName -and -not [string]::Equals($given, [string]$row.GivenName, [StringComparison]::Ordinal)) {
            "{0}: given name '{1}' should be '{2}'" -f $row.Key, $given, $row.GivenName
        }
        if ($row.FamilyName -and -not [string]::Equals($family, [string]$row.FamilyName, [StringComparison]::Ordinal)) {
            "{0}: family name '{1}' should be '{2}'" -f $row.Key, $family, $row.FamilyName
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User names' -Compared $compared -Mismatch @($mismatch)))

    # --- Groups, applications, resources, attributes ---------------------------------------
    $groupRows = & $read 'PingOneGroups.csv'
    $groups = @(Get-PingOneSeededObject -Type Groups -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $displayOf $_.Name }) `
                -Found @($groups | ForEach-Object { [string]$_.name })))

    $applicationRows = & $read 'PingOneApplications.csv'
    $applications = @(Get-PingOneSeededObject -Type Applications -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Applications' `
                -Expected @($applicationRows | ForEach-Object { & $displayOf $_.Name }) `
                -Found @($applications | ForEach-Object { [string]$_.name })))

    $resourceRows = & $read 'PingOneResources.csv'
    $resources = @(Get-PingOneSeededObject -Type Resources -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Resources' `
                -Expected @($resourceRows | ForEach-Object { & $displayOf $_.Name }) `
                -Found @($resources | ForEach-Object { [string]$_.name })))

    $attributeRows = & $read 'PingOneProfileAttributes.csv'
    $attributes = @(Get-PingOneSeededObject -Type Attributes -Connection $connection)
    $checks.Add((New-TestEnvironmentCheck -Name 'Attributes' -FoundCount $attributes.Count -ExpectedCount $attributeRows.Count))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership) {
        # A user row names its groups by their row key; the environment names them by display name.
        $groupNameByKey = @{}
        foreach ($row in $groupRows) { $groupNameByKey[$row.Key] = & $displayOf $row.Name }
        $groupNameById = @{}
        foreach ($group in $groups) { $groupNameById[[string]$group.id] = [string]$group.name }

        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $foundPairs = New-Object System.Collections.Generic.List[string]
        foreach ($row in $userRows) {
            $keys = @($row.Groups -split ';' | Where-Object { $_ })
            if ($keys.Count -eq 0) { continue }
            $username = & $usernameOf $row.Key
            foreach ($key in $keys) {
                $groupName = if ($groupNameByKey.ContainsKey($key)) { $groupNameByKey[$key] } else { & $displayOf $key }
                $expectedPairs.Add(('{0} <- {1}' -f $groupName, $username))
            }

            $user = $userByName[$username.ToLowerInvariant()]
            if (-not $user) { continue }
            try {
                foreach ($membership in @(Invoke-PingOneRequest -Method GET -Path "users/$($user.id)/memberOfGroups" -Paginate -Connection $connection)) {
                    if ($null -eq $membership) { continue }
                    $groupName = if ($membership.name) { [string]$membership.name } else { $groupNameById[[string]$membership.id] }
                    if ($groupName) { $foundPairs.Add(('{0} <- {1}' -f $groupName, [string]$user.username)) }
                }
            }
            catch {
                Write-Warning "Could not read the groups of '$username': $($_.Exception.Message). They are counted as missing."
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -IgnoreCase -MissingOnly))
    }

    return New-TestEnvironmentVerification -Provider 'PingOne' -Target $connection.EnvironmentId -Check $checks.ToArray() -Quiet:$Quiet
}
