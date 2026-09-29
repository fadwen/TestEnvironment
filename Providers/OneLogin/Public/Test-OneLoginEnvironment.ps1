function Test-OneLoginEnvironment {
    <#
    .SYNOPSIS
        Verifies that the seeded OneLogin account matches the seed data
    .DESCRIPTION
        Reads everything the module owns in the connected account, the same way teardown finds it,
        and compares it with the seed files: every seeded name should be present, nothing the module owns should be
        there that the data does not describe, every user's first and last name should match the
        data by codepoint, every lifecycle status and state and every manager should be the one the
        data gives - a Locked person locked for at least another day - every directory identifier
        should be the one the seed builds, and every group, role, app grant, policy, policy
        setting, API scope, claim and client, app rule, Smart Hook and sign-up profile the data
        describes should be in place. How many seeded people hold a pre-enrolled MFA factor is
        counted but not judged, because the seed enrols one only where the account offers it.

        Names are compared ordinally, not with -eq, because a decomposed and a precomposed name
        are equal to -eq and different on the wire; a name that came back mangled is the fault
        this exists to catch. Usernames are compared case-insensitively.

        Role memberships and app grants are judged on what is missing only: an enabled mapping
        adds people to a role that the data never lists there, and that is not a fault. OneLogin
        also settles role membership a few seconds after it is written, so a verification run in
        the same breath as the seed can report memberships missing that a second run finds.
    .PARAMETER SkipMembership
        Do not judge role memberships and app grants
    .PARAMETER Quiet
        Return the result without writing to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification. Passed is $true when every check passed.
    .EXAMPLE
        PS> Test-OneLoginEnvironment

        Prints one line per check and returns the result.
    .EXAMPLE
        PS> Test-OneLoginEnvironment -SkipMembership -Quiet | Select-Object -ExpandProperty Checks

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

    $connection = Get-OneLoginConnection
    $dataPath = Get-OneLoginDataPath
    $checks = New-Object System.Collections.Generic.List[object]

    $read = { param($file) @(Import-Csv -LiteralPath (Join-Path -Path $dataPath -ChildPath $file) -Encoding UTF8) }
    $displayOf = { param($key) Resolve-OneLoginSeedName -Key $key -Kind DisplayName -Connection $connection }
    $usernameOf = { param($key) Resolve-OneLoginSeedName -Key $key -Kind Username -Connection $connection }

    $attributeRows = @(& $read 'OneLoginCustomAttributes.csv')
    $roleRows = @(& $read 'OneLoginRoles.csv')
    $groupRows = @(& $read 'OneLoginGroups.csv')
    $appRows = @(& $read 'OneLoginApps.csv')
    $mappingRows = @(& $read 'OneLoginMappings.csv')
    $userRows = @(& $read 'OneLoginUsers.csv')
    $policyRows = @(& $read 'OneLoginPolicies.csv')
    $apiRows = @(& $read 'OneLoginApiAuthorizations.csv')
    $ruleRows = @(& $read 'OneLoginAppRules.csv')
    $hookRows = @(& $read 'OneLoginHooks.csv')
    $registrationRows = @(& $read 'OneLoginSelfRegistrations.csv')

    $attributes = @(Get-OneLoginSeededObject -Type Attributes -Connection $connection)
    $users = @(Get-OneLoginSeededObject -Type Users -Connection $connection)
    $apps = @(Get-OneLoginSeededObject -Type Apps -Connection $connection)
    $userIds = @($users | ForEach-Object { [string]$_.id })
    $roles = @(Get-OneLoginSeededObject -Type Roles -OwnedUserId $userIds -OwnedAppId @($apps | ForEach-Object { [string]$_.id }) -Connection $connection)
    $groups = @(Get-OneLoginSeededObject -Type Groups -OwnedUserId $userIds -Connection $connection)
    $roleIds = @($roles | ForEach-Object { [string]$_.id })
    $owned = @{ OwnedUserId = $userIds; OwnedAppId = @($apps | ForEach-Object { [string]$_.id }); OwnedRoleId = $roleIds; OwnedGroupId = @($groups | ForEach-Object { [string]$_.id }); Connection = $connection }
    $mappings = @(Get-OneLoginSeededObject -Type Mappings @owned)
    $policies = @(Get-OneLoginSeededObject -Type Policies @owned)
    $apiServers = @(Get-OneLoginSeededObject -Type ApiAuthorizations -Connection $connection)
    $appRules = @(Get-OneLoginSeededObject -Type AppRules @owned)
    $hooks = @(Get-OneLoginSeededObject -Type Hooks @owned)
    $registrations = @(Get-OneLoginSeededObject -Type SelfRegistration -Connection $connection)

    # --- Objects -----------------------------------------------------------------------------
    $checks.Add((New-TestEnvironmentCheck -Name 'Attributes' -FoundCount $attributes.Count -ExpectedCount $attributeRows.Count))
    $checks.Add((New-TestEnvironmentCheck -Name 'Roles' `
                -Expected @($roleRows | ForEach-Object { & $displayOf $_.Name }) -Found @($roles | ForEach-Object { [string]$_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'Groups' `
                -Expected @($groupRows | ForEach-Object { & $displayOf $_.Name }) -Found @($groups | ForEach-Object { [string]$_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'Apps' `
                -Expected @($appRows | ForEach-Object { & $displayOf $_.Name }) -Found @($apps | ForEach-Object { [string]$_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'Mappings' `
                -Expected @($mappingRows | ForEach-Object { & $displayOf $_.Name }) -Found @($mappings | ForEach-Object { [string]$_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'Users' `
                -Expected @($userRows | ForEach-Object { & $usernameOf $_.Key }) -Found @($users | ForEach-Object { [string]$_.username }) -IgnoreCase))
    $checks.Add((New-TestEnvironmentCheck -Name 'Policies' `
                -Expected @($policyRows | ForEach-Object { & $displayOf $_.Name }) -Found @($policies | ForEach-Object { [string]$_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'API authorizations' `
                -Expected @($apiRows | ForEach-Object { & $displayOf $_.Name }) -Found @($apiServers | ForEach-Object { [string]$_.name })))
    $appNameByKey = @{}
    foreach ($row in $appRows) { $appNameByKey[$row.Key] = & $displayOf $row.Name }
    $appNameById = @{}
    foreach ($app in $apps) { $appNameById[[string]$app.id] = [string]$app.name }
    $checks.Add((New-TestEnvironmentCheck -Name 'App rules' `
                -Expected @($ruleRows | ForEach-Object { '{0} : {1}' -f $appNameByKey[$_.App], (& $displayOf $_.Name) }) `
                -Found @($appRules | ForEach-Object { '{0} : {1}' -f $appNameById[[string]$_.AppId], $_.name })))
    $checks.Add((New-TestEnvironmentCheck -Name 'Smart hooks' -FoundCount $hooks.Count -ExpectedCount $hookRows.Count))
    $checks.Add((New-TestEnvironmentCheck -Name 'Self-registration' `
                -Expected @($registrationRows | ForEach-Object { & $displayOf $_.Name }) -Found @($registrations | ForEach-Object { [string]$_.name })))

    # --- Policies ----------------------------------------------------------------------------
    # Which group each policy governs, and the settings the data gives it.
    $groupNameByKeyForPolicy = @{}
    foreach ($row in $groupRows) { $groupNameByKeyForPolicy[$row.Key] = & $displayOf $row.Name }
    $policyNameById = @{}
    foreach ($policy in $policies) { $policyNameById[[string]$policy.id] = [string]$policy.name }
    $expectedPolicy = foreach ($row in $policyRows) {
        foreach ($key in @(([string]$row.Groups -split ';') | Where-Object { $_ })) { '{0} <- {1}' -f $groupNameByKeyForPolicy[$key], (& $displayOf $row.Name) }
    }
    $foundPolicy = foreach ($group in $groups) {
        if ($group.policy_id -and $policyNameById.ContainsKey([string]$group.policy_id)) { '{0} <- {1}' -f $group.name, $policyNameById[[string]$group.policy_id] }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'Group policies' -Expected @($expectedPolicy) -Found @($foundPolicy)))

    $settingField = [ordered]@{
        MinimumPasswordLength = 'minimum_password_length'; PasswordExpirationDays = 'password_expiration_days'; PasswordsRemembered = 'passwords_remembered'
        MaximumInvalidLoginAttempts = 'maximum_invalid_login_attempts'; LockEffectiveMinutes = 'lock_effective_minutes'
    }
    $settingsCompared = 0
    $settingMismatch = New-Object System.Collections.Generic.List[string]
    foreach ($row in $policyRows) {
        $policy = @($policies | Where-Object { [string]$_.name -eq (& $displayOf $row.Name) }) | Select-Object -First 1
        if (-not $policy) { continue }
        $settingsCompared++
        $detail = Invoke-OneLoginRequest -Method GET -Path "policies/$($policy.id)" -Connection $connection
        foreach ($column in $settingField.Keys) {
            if ($row.$column -and [string]$detail.($settingField[$column]) -ne [string]$row.$column) {
                $settingMismatch.Add(('{0}: {1} is {2}, should be {3}' -f $row.Key, $settingField[$column], $detail.($settingField[$column]), $row.$column))
            }
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'Policy settings' -Compared $settingsCompared -Mismatch $settingMismatch.ToArray()))

    # --- API authorizations ------------------------------------------------------------------
    $expectedScope = New-Object System.Collections.Generic.List[string]
    $foundScope = New-Object System.Collections.Generic.List[string]
    $expectedClaim = New-Object System.Collections.Generic.List[string]
    $foundClaim = New-Object System.Collections.Generic.List[string]
    $expectedClient = New-Object System.Collections.Generic.List[string]
    $foundClient = New-Object System.Collections.Generic.List[string]
    $listOf = { param([string]$Path) @(Invoke-OneLoginRequest -Method GET -Path $Path -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ }) }
    foreach ($row in $apiRows) {
        $serverName = & $displayOf $row.Name
        foreach ($entry in @(([string]$row.Scopes -split '\|') | Where-Object { $_ })) { $expectedScope.Add(('{0} : {1}' -f $serverName, ($entry -split '=', 2)[0])) }
        foreach ($entry in @(([string]$row.Claims -split '\|') | Where-Object { $_ })) { $expectedClaim.Add(('{0} : {1}' -f $serverName, ($entry -split '=', 2)[0])) }
        foreach ($entry in @(([string]$row.Clients -split '\|') | Where-Object { $_ })) {
            $appKey, $scopeList = $entry -split '=', 2
            foreach ($scope in @(([string]$scopeList -split ' ') | Where-Object { $_ })) { $expectedClient.Add(('{0} <- {1} : {2}' -f $serverName, $appNameByKey[$appKey], $scope)) }
        }
    }
    foreach ($server in $apiServers) {
        foreach ($scope in (& $listOf "api_authorizations/$($server.id)/scopes")) { $foundScope.Add(('{0} : {1}' -f $server.name, $scope.value)) }
        foreach ($claim in (& $listOf "api_authorizations/$($server.id)/claims")) { $foundClaim.Add(('{0} : {1}' -f $server.name, $claim.name)) }
        foreach ($client in (& $listOf "api_authorizations/$($server.id)/clients")) {
            $clientName = if ($appNameById.ContainsKey([string]$client.app_id)) { $appNameById[[string]$client.app_id] } else { "app $($client.app_id)" }
            foreach ($scope in @($client.scopes | Where-Object { $null -ne $_ })) { $foundClient.Add(('{0} <- {1} : {2}' -f $server.name, $clientName, $scope.value)) }
        }
    }
    $checks.Add((New-TestEnvironmentCheck -Name 'API scopes' -Expected $expectedScope -Found $foundScope))
    # The claims OneLogin adds to every server are not the data's to list, so a claim is judged on
    # what is missing only.
    $checks.Add((New-TestEnvironmentCheck -Name 'API claims' -Expected $expectedClaim -Found $foundClaim -MissingOnly))
    $checks.Add((New-TestEnvironmentCheck -Name 'API clients' -Expected $expectedClient -Found $foundClient))

    # --- People ------------------------------------------------------------------------------
    $userByLogin = @{}
    $loginById = @{}
    foreach ($user in $users) {
        if ($user.username) { $userByLogin[([string]$user.username).ToLowerInvariant()] = $user }
        $loginById[[string]$user.id] = [string]$user.username
    }
    $groupNameByKey = @{}
    foreach ($row in $groupRows) { $groupNameByKey[$row.Key] = & $displayOf $row.Name }
    $groupNameById = @{}
    foreach ($group in $groups) { $groupNameById[[string]$group.id] = [string]$group.name }

    $compared = 0
    $nameMismatch = New-Object System.Collections.Generic.List[string]
    $lifecycleMismatch = New-Object System.Collections.Generic.List[string]
    $managerMismatch = New-Object System.Collections.Generic.List[string]
    $managersCompared = 0
    $directoryMismatch = New-Object System.Collections.Generic.List[string]
    $roleDataName = @{}
    foreach ($row in $roleRows) { $roleDataName[$row.Key] = $row.Name }
    $groupDataName = @{}
    foreach ($row in $groupRows) { $groupDataName[$row.Key] = $row.Name }
    $withFactor = 0
    $expectedGroup = New-Object System.Collections.Generic.List[string]
    $foundGroup = New-Object System.Collections.Generic.List[string]

    foreach ($row in $userRows) {
        $login = & $usernameOf $row.Key
        $user = $userByLogin[$login.ToLowerInvariant()]
        if ($row.Group) { $expectedGroup.Add(('{0} <- {1}' -f $groupNameByKey[$row.Group], $login)) }
        if (-not $user) { continue }
        $compared++

        if (-not [string]::Equals([string]$user.firstname, [string]$row.GivenName, [StringComparison]::Ordinal)) {
            $nameMismatch.Add(("{0}: first name '{1}' should be '{2}'" -f $row.Key, $user.firstname, $row.GivenName))
        }
        if (-not [string]::Equals([string]$user.lastname, [string]$row.Surname, [StringComparison]::Ordinal)) {
            $nameMismatch.Add(("{0}: last name '{1}' should be '{2}'" -f $row.Key, $user.lastname, $row.Surname))
        }
        if ([int]$user.status -ne [int]$script:OneLoginUserStatus[$row.Status]) {
            $lifecycleMismatch.Add(('{0}: status {1} should be {2} ({3})' -f $row.Key, $user.status, $script:OneLoginUserStatus[$row.Status], $row.Status))
        }
        elseif ($row.Status -eq 'Locked') {
            $until = $null
            if ($user.locked_until) { try { $until = [datetime]$user.locked_until } catch { $until = $null } }
            if (-not $until -or $until -lt (Get-Date).AddDays(1)) {
                $lifecycleMismatch.Add(('{0}: locked until {1}, which is less than a day away' -f $row.Key, $user.locked_until))
            }
        }
        $directory = Resolve-OneLoginDirectoryIdentity -Row $row -RoleNameByKey $roleDataName -GroupNameByKey $groupDataName -Connection $connection
        foreach ($name in $directory.Keys) {
            if (-not [string]::Equals([string]$user.$name, [string]$directory[$name], [StringComparison]::Ordinal)) {
                $directoryMismatch.Add(("{0}: {1} '{2}' should be '{3}'" -f $row.Key, $name, $user.$name, $directory[$name]))
            }
        }
        if ($row.Mfa) {
            $devices = @(Invoke-OneLoginRequest -Method GET -Path "mfa/users/$($user.id)/devices" -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
            if ($devices.Count -gt 0) { $withFactor++ }
        }
        if ([int]$user.state -ne [int]$script:OneLoginUserState[$row.State]) {
            $lifecycleMismatch.Add(('{0}: state {1} should be {2} ({3})' -f $row.Key, $user.state, $script:OneLoginUserState[$row.State], $row.State))
        }
        if ($row.Manager) {
            $managersCompared++
            $manager = $userByLogin[(& $usernameOf $row.Manager).ToLowerInvariant()]
            $actual = if ($user.manager_user_id) { $loginById[[string]$user.manager_user_id] } else { $null }
            if (-not $manager -or [string]$user.manager_user_id -ne [string]$manager.id) {
                $shown = if ($actual) { $actual } elseif ($user.manager_user_id) { "user $($user.manager_user_id)" } else { 'nobody' }
                $managerMismatch.Add(('{0}: manager is {1}, should be {2}' -f $row.Key, $shown, (& $usernameOf $row.Manager)))
            }
        }
        if ($user.group_id -and $groupNameById.ContainsKey([string]$user.group_id)) {
            $foundGroup.Add(('{0} <- {1}' -f $groupNameById[[string]$user.group_id], [string]$user.username))
        }
    }

    $checks.Add((New-TestEnvironmentCheck -Name 'User names' -Compared $compared -Mismatch $nameMismatch.ToArray()))
    $checks.Add((New-TestEnvironmentCheck -Name 'User lifecycle' -Compared $compared -Mismatch $lifecycleMismatch.ToArray()))
    $checks.Add((New-TestEnvironmentCheck -Name 'Managers' -Compared $managersCompared -Mismatch $managerMismatch.ToArray()))
    $checks.Add((New-TestEnvironmentCheck -Name 'Directory fields' -Compared $compared -Mismatch $directoryMismatch.ToArray()))
    # Observational: a factor is enrolled only where the account offers it.
    $checks.Add((New-TestEnvironmentCheck -Name 'MFA factors' -FoundCount $withFactor))
    $checks.Add((New-TestEnvironmentCheck -Name 'Group membership' -Expected $expectedGroup -Found $foundGroup -IgnoreCase -MissingOnly))

    # --- Access ------------------------------------------------------------------------------
    if (-not $SkipMembership) {
        $roleNameByKey = @{}
        foreach ($row in $roleRows) { $roleNameByKey[$row.Key] = & $displayOf $row.Name }
        $expectedRole = New-Object System.Collections.Generic.List[string]
        foreach ($row in $userRows) {
            foreach ($key in @(([string]$row.Roles -split ';') | Where-Object { $_ })) {
                $expectedRole.Add(('{0} <- {1}' -f $roleNameByKey[$key], (& $usernameOf $row.Key)))
            }
        }
        $foundRole = New-Object System.Collections.Generic.List[string]
        $expectedGrant = New-Object System.Collections.Generic.List[string]
        foreach ($row in $appRows) {
            foreach ($key in @(([string]$row.Roles -split ';') | Where-Object { $_ })) {
                $expectedGrant.Add(('{0} <- {1}' -f $roleNameByKey[$key], (& $displayOf $row.Name)))
            }
        }
        $foundGrant = New-Object System.Collections.Generic.List[string]
        foreach ($role in $roles) {
            foreach ($id in @($role.users | Where-Object { $null -ne $_ })) {
                if ($loginById.ContainsKey([string]$id)) { $foundRole.Add(('{0} <- {1}' -f $role.name, $loginById[[string]$id])) }
            }
            foreach ($id in @($role.apps | Where-Object { $null -ne $_ })) {
                if ($appNameById.ContainsKey([string]$id)) { $foundGrant.Add(('{0} <- {1}' -f $role.name, $appNameById[[string]$id])) }
            }
        }

        $checks.Add((New-TestEnvironmentCheck -Name 'Role memberships' -Expected $expectedRole -Found $foundRole -IgnoreCase -MissingOnly))
        $checks.Add((New-TestEnvironmentCheck -Name 'App assignments' -Expected $expectedGrant -Found $foundGrant -MissingOnly))
    }

    return New-TestEnvironmentVerification -Provider 'OneLogin' -Target $connection.Subdomain -Check $checks.ToArray() -Quiet:$Quiet
}
