function Test-OktaEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded Okta org matches the seed data
    .DESCRIPTION
        Reads the users, groups and applications the module owns in the connected org, the same
        way teardown finds them, and compares them with the seed files: every seeded login, group
        name and application label should be present, nothing the module owns should be there that
        the data does not describe, every display name should match the data by codepoint, and
        every membership a group row lists should hold.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name are
        equal to -eq and different on the wire; a name that came back mangled is the fault this
        exists to catch. Logins are compared case-insensitively because Okta folds them.

        Memberships are judged on what is missing only: a group rule adds members the data never
        lists, and that is not a fault.

        An org whose active-user limit stopped the seed short reports the users it could not create
        as missing. That is the truth of the org, and the report says so rather than adjusting the
        expectation.
    .PARAMETER SkipMembership
        Do not read group memberships, which costs one call per seeded group
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-OktaEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> if (-not (Test-OktaEnvironment -Quiet).Passed) { throw 'The Okta seed is incomplete.' }

        Gates a script on the org matching the data.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipMembership,

        [Parameter()]
        [switch]$Quiet
    )

    $connection = Get-OktaConnection
    $dataPath = Get-OktaDataPath
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    $loginOf = { param($loginPrefix) '{0}@{1}' -f $loginPrefix, $connection.EmailDomain }
    $named = { param($name) '{0}-{1}' -f $connection.Prefix, $name }

    # --- Users -----------------------------------------------------------------------------
    $userRows = & $read 'OktaUsers.csv'
    $users = @(Get-OktaSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { & $loginOf $_.LoginPrefix }) `
                -Found @($users | ForEach-Object { [string]$_.profile.login }) -IgnoreCase))

    $userByLogin = @{}
    foreach ($user in $users) {
        if ($user.profile.login) { $userByLogin[([string]$user.profile.login).ToLowerInvariant()] = $user }
    }
    $compared = 0
    $mismatch = foreach ($row in $userRows) {
        if (-not $row.DisplayName) { continue }
        $user = $userByLogin[(& $loginOf $row.LoginPrefix).ToLowerInvariant()]
        if (-not $user) { continue }
        $compared++
        if (-not [string]::Equals([string]$user.profile.displayName, [string]$row.DisplayName, [StringComparison]::Ordinal)) {
            "{0}: '{1}' should be '{2}'" -f $row.LoginPrefix, $user.profile.displayName, $row.DisplayName
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'User display names' -Compared $compared -Mismatch @($mismatch)))

    # --- Groups and applications -----------------------------------------------------------
    $groupRows = & $read 'OktaGroups.csv'
    $groups = @(Get-OktaSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $named $_.DisplayName }) `
                -Found @($groups | ForEach-Object { [string]$_.profile.name })))

    $appRows = & $read 'OktaApps.csv'
    $apps = @(Get-OktaSeededApp -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
    $checks.Add((New-TestEnvironmentCheck -Name 'Applications' `
                -Expected @($appRows | ForEach-Object { & $named $_.Label }) `
                -Found @($apps | ForEach-Object { [string]$_.label })))

    # --- Memberships -----------------------------------------------------------------------
    if (-not $SkipMembership) {
        $groupByName = @{}
        foreach ($group in $groups) { if ($group.profile.name) { $groupByName[[string]$group.profile.name] = $group } }

        $expectedPairs = New-Object System.Collections.Generic.List[string]
        $foundPairs = New-Object System.Collections.Generic.List[string]
        foreach ($row in $groupRows) {
            $members = @($row.Members -split ';' | Where-Object { $_ })
            if ($members.Count -eq 0) { continue }
            $groupName = & $named $row.DisplayName
            foreach ($member in $members) { $expectedPairs.Add(('{0} <- {1}' -f $groupName, (& $loginOf $member))) }

            $group = $groupByName[$groupName]
            if (-not $group) { continue }
            try {
                foreach ($user in @(Invoke-OktaRequest -Method GET -Path "/api/v1/groups/$($group.id)/users" -Query @{ limit = 200 } -Paginate)) {
                    if ($user.profile.login) { $foundPairs.Add(('{0} <- {1}' -f $groupName, [string]$user.profile.login)) }
                }
            }
            catch {
                Write-Warning "Could not read the members of '$groupName': $($_.Exception.Message). They are counted as missing."
            }
        }
        $checks.Add((New-TestEnvironmentCheck -Name 'Group memberships' -Expected $expectedPairs -Found $foundPairs -IgnoreCase -MissingOnly))
    }

    return New-TestEnvironmentVerification -Provider 'Okta' -Target $connection.OrgUrl -Check $checks.ToArray() -Quiet:$Quiet
}
