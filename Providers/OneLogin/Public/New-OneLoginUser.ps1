function New-OneLoginUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded people with their lifecycle, group, manager and roles, and puts a reused one back as the data describes
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Username,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    $dataPath = Get-OneLoginDataPath
    $attribute = $script:OneLoginSeedAttribute

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginUsers.csv') -Encoding UTF8)
    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($Username) { $rows = @($rows | Where-Object { $Username -contains $_.Key }) }

    $groupNameByKey = @{}
    foreach ($groupRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginGroups.csv') -Encoding UTF8)) {
        $groupNameByKey[$groupRow.Key] = Resolve-OneLoginSeedName -Key $groupRow.Name -Kind DisplayName -Connection $connection
    }
    $roleNameByKey = @{}
    $roleDataName = @{}
    foreach ($roleRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginRoles.csv') -Encoding UTF8)) {
        $roleNameByKey[$roleRow.Key] = Resolve-OneLoginSeedName -Key $roleRow.Name -Kind DisplayName -Connection $connection
        $roleDataName[$roleRow.Key] = $roleRow.Name
    }
    $groupDataName = @{}
    foreach ($groupRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginGroups.csv') -Encoding UTF8)) { $groupDataName[$groupRow.Key] = $groupRow.Name }

    # The people already seeded, by username, and the roles and groups the seed may put people in:
    # its own, or empty ones of its names. Nobody is ever added to a role or group holding someone
    # this module did not make, and only ids from this list and from users created below are ever
    # sent anywhere, so no real person can be moved, managed or given a role by the seed.
    $seededByLogin = @{}
    $idByKey = @{}
    foreach ($user in @(Get-OneLoginSeededObject -Type Users -Connection $connection)) {
        $login = ([string]$user.username).ToLowerInvariant()
        $seededByLogin[$login] = $user
        $idByKey[$login.Substring($marker.Prefix.Length)] = [string]$user.id
    }
    $ownedIds = @($idByKey.Values)
    $groupByName = @{}
    foreach ($group in @(Get-OneLoginSeededObject -Type Groups -AllowEmpty -OwnedUserId $ownedIds -Connection $connection)) {
        $groupByName[[string]$group.name] = $group
    }
    $roleByName = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -OwnedUserId $ownedIds -Connection $connection)) {
        $roleByName[[string]$role.name] = $role
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $updated = 0
    $deferredManager = [System.Collections.Generic.List[object]]::new()
    $toLock = [System.Collections.Generic.List[object]]::new()
    $roleMembers = @{}
    $index = 0

    foreach ($row in $rows) {
        $index++
        $login = Resolve-OneLoginSeedName -Key $row.Key -Kind Username -Connection $connection
        Write-TestProgress -Activity 'Creating OneLogin users' -Status $login `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $script:OneLoginUserStatus.Contains($row.Status) -or -not $script:OneLoginUserState.Contains($row.State)) {
            $errors.Add("User $login has status '$($row.Status)' and state '$($row.State)', which the provider does not know")
            continue
        }

        # What the data says the person is. Locked is not a status the seed sends - a status of 3
        # unlocks itself fifteen minutes later - so a Locked person is created Active and locked
        # afterwards through the lock call, and their status is never sent again.
        $locked = $row.Status -eq 'Locked'
        $desired = [ordered]@{
            firstname  = $row.GivenName
            lastname   = $row.Surname
            title      = $row.Title
            department = $row.Department
            company    = $row.Company
            status     = $(if ($locked) { $script:OneLoginUserStatus['Active'] } else { $script:OneLoginUserStatus[$row.Status] })
            state      = $script:OneLoginUserState[$row.State]
        }
        # The directory identifiers, every one of them in the seed's namespace, so none can name or be
        # matched to a real AD account, UPN or employee.
        $directory = Resolve-OneLoginDirectoryIdentity -Row $row -RoleNameByKey $roleDataName -GroupNameByKey $groupDataName -Connection $connection
        $fields = [ordered]@{ $attribute = $marker.Tag }
        $fields['zztest_contractor'] = ([string]$row.Contractor).ToLowerInvariant()
        if ($row.BadgeId) { $fields['zztest_badge_id'] = $row.BadgeId }
        if ($row.CostCenter) { $fields['zztest_cost_center'] = $row.CostCenter }

        $groupId = $null
        if ($row.Group) {
            $group = $groupByName[$groupNameByKey[$row.Group]]
            if ($group) { $groupId = [string]$group.id }
            else { $errors.Add("Group '$($row.Group)' for $login does not exist, or is not one the seed may use; run New-OneLoginGroup first") }
        }

        $managerId = $null
        if ($row.Manager) {
            if ($idByKey.ContainsKey($row.Manager)) { $managerId = $idByKey[$row.Manager] }
            else { $deferredManager.Add([PSCustomObject]@{ Key = $row.Key; Login = $login; Manager = $row.Manager }) }
        }

        $existing = $seededByLogin[$login]
        if ($existing) {
            # Put back what differs, so a repair restores a person rather than only a missing one.
            # Names are compared ordinally: a decomposed name that came back precomposed is wrong.
            $change = [ordered]@{}
            foreach ($name in 'firstname', 'lastname', 'title', 'department', 'company') {
                if (-not [string]::Equals([string]$existing.$name, [string]$desired[$name], [StringComparison]::Ordinal)) {
                    $change[$name] = $desired[$name]
                }
            }
            if (-not $locked -and [int]$existing.status -ne $desired.status) { $change['status'] = $desired.status }
            foreach ($name in $directory.Keys) {
                if (-not [string]::Equals([string]$existing.$name, [string]$directory[$name], [StringComparison]::Ordinal)) { $change[$name] = $directory[$name] }
            }
            if ([int]$existing.state -ne $desired.state) { $change['state'] = $desired.state }
            if ([string]$existing.group_id -ne [string]$groupId -and $groupId) { $change['group_id'] = [long]$groupId }
            if ($managerId -and [string]$existing.manager_user_id -ne $managerId) { $change['manager_user_id'] = [long]$managerId }
            $fieldChange = [ordered]@{}
            foreach ($name in $fields.Keys) {
                $current = $null
                if ($existing.custom_attributes) { $current = [string]$existing.custom_attributes.$name }
                if (-not [string]::Equals($current, [string]$fields[$name], [StringComparison]::Ordinal)) { $fieldChange[$name] = $fields[$name] }
            }
            if ($fieldChange.Count -gt 0) { $change['custom_attributes'] = $fieldChange }

            $reused.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Id = [string]$existing.id })
            if ($change.Count -gt 0 -and $PSCmdlet.ShouldProcess($login, ('Update OneLogin user ({0})' -f (@($change.Keys) -join ', ')))) {
                try {
                    $null = Invoke-OneLoginRequest -Method PUT -Path "users/$($existing.id)" -Body $change -Connection $connection
                    $updated++
                }
                catch {
                    $errors.Add("Could not update user ${login}: $($_.Exception.Message)")
                }
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($login, 'Create OneLogin user')) { continue }

            $body = [ordered]@{
                username = $login
                email    = Resolve-OneLoginSeedName -Key $row.Key -Kind Email -Connection $connection
            }
            foreach ($name in $desired.Keys) { if ($null -ne $desired[$name] -and $desired[$name] -ne '') { $body[$name] = $desired[$name] } }
            foreach ($name in $directory.Keys) { if ($directory[$name]) { $body[$name] = $directory[$name] } }
            if ($groupId) { $body['group_id'] = [long]$groupId }
            if ($managerId) { $body['manager_user_id'] = [long]$managerId }
            $body['custom_attributes'] = $fields

            try {
                $user = Invoke-OneLoginRequest -Method POST -Path 'users' -Body $body -Connection $connection
                $idByKey[$row.Key] = [string]$user.id
                $created.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Id = [string]$user.id })
            }
            catch {
                # A 422 here is usually a username or email that already exists. It is not one this
                # module seeded - those were found above - so it is left alone.
                $errors.Add("Could not create user ${login}: $($_.Exception.Message)")
                Write-Warning "Could not create user ${login}: $($_.Exception.Message)"
                continue
            }
        }

        if ($locked -and $idByKey[$row.Key]) {
            # Locked again when the lock is missing or has less than a month left, so a repair or a
            # re-run keeps the person locked however old the seed is.
            $lockedUntil = $null
            if ($existing -and $existing.locked_until) { try { $lockedUntil = [datetime]$existing.locked_until } catch { $lockedUntil = $null } }
            if (-not $existing -or [int]$existing.status -ne $script:OneLoginUserStatus['Locked'] -or -not $lockedUntil -or $lockedUntil -lt (Get-Date).AddDays(30)) {
                $toLock.Add([PSCustomObject]@{ Id = $idByKey[$row.Key]; Login = $login })
            }
        }

        foreach ($roleKey in @(([string]$row.Roles -split ';') | Where-Object { $_ })) {
            if (-not $roleMembers.ContainsKey($roleKey)) { $roleMembers[$roleKey] = New-Object System.Collections.Generic.List[string] }
            $roleMembers[$roleKey].Add($idByKey[$row.Key])
        }
    }

    # The locks, through the version 1 call, which takes a duration where the status field does not.
    # Only a licensed person can be locked; OneLogin refuses an unlicensed one, and says so.
    $lockedCount = 0
    foreach ($pending in $toLock) {
        if (-not $PSCmdlet.ShouldProcess($pending.Login, 'Lock OneLogin user for a year')) { continue }
        try {
            $null = Invoke-OneLoginRequest -Method PUT -Path "/api/1/users/$($pending.Id)/lock_user" -Body @{ locked_until = $script:OneLoginLockMinutes } -Connection $connection
            $lockedCount++
        }
        catch { $errors.Add("Could not lock $($pending.Login): $($_.Exception.Message)") }
    }

    Write-TestProgress -Activity 'Creating OneLogin users' -Completed -ShowProgress:$ShowProgress

    # Managers the file order could not provide at creation: a manager outside the rows being
    # seeded, or one seeded later. A manager who is not seeded at all is left unset rather than
    # looked up among real people.
    $managersSet = 0
    foreach ($pending in $deferredManager) {
        $userId = $idByKey[$pending.Key]
        $managerId = $idByKey[$pending.Manager]
        if (-not $userId) { continue }
        if (-not $managerId) {
            Write-Warning "The manager '$($pending.Manager)' of $($pending.Login) is not seeded; the manager is left unset"
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($pending.Login, 'Set OneLogin manager')) { continue }
        try {
            $null = Invoke-OneLoginRequest -Method PUT -Path "users/$userId" -Body @{ manager_user_id = [long]$managerId } -Connection $connection
            $managersSet++
        }
        catch {
            $errors.Add("Could not set the manager of $($pending.Login): $($_.Exception.Message)")
        }
    }

    # Roles, one request per role for everyone it is missing. OneLogin settles role membership a
    # few seconds after it is written, so what a role holds is read from the listing taken at the
    # start of the step rather than re-read after each write.
    $membershipsApplied = 0
    $grantedTo = @{}
    foreach ($roleKey in ($roleMembers.Keys | Sort-Object)) {
        $role = $roleByName[$roleNameByKey[$roleKey]]
        if (-not $role) {
            $errors.Add("Role '$roleKey' does not exist, or is not one the seed may use; run New-OneLoginRole first")
            continue
        }
        $current = @($role.users | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        $missing = @($roleMembers[$roleKey] | Where-Object { $_ -and $current -notcontains $_ } | Sort-Object -Unique)
        if ($missing.Count -eq 0) { continue }

        if (-not $PSCmdlet.ShouldProcess("$($role.name) <- $($missing.Count) user(s)", 'Add OneLogin role members')) { continue }

        for ($offset = 0; $offset -lt $missing.Count; $offset += 100) {
            $batch = @($missing[$offset..([Math]::Min($offset + 99, $missing.Count - 1))])
            # Written as JSON here: piped to ConvertTo-Json a one-element array becomes a bare
            # number, and the endpoint wants a list.
            try {
                $null = Invoke-OneLoginRequest -Method POST -Path "roles/$($role.id)/users" -Body ('[{0}]' -f ($batch -join ',')) -Connection $connection
                $membershipsApplied += $batch.Count
                if (-not $grantedTo.ContainsKey([string]$role.id)) { $grantedTo[[string]$role.id] = New-Object System.Collections.Generic.List[string] }
                foreach ($id in $batch) { $grantedTo[[string]$role.id].Add([string]$id) }
            }
            catch {
                $errors.Add("Could not add $($batch.Count) user(s) to role $($role.name): $($_.Exception.Message)")
            }
        }
    }

    # OneLogin shows a role grant a few seconds after answering it - ten, measured on a trial. On some
    # runs, verified live, it answers 200 and applies nothing: twelve of thirteen grants were still
    # absent two minutes later, and on another run grants that had sat unapplied for minutes appeared
    # within seconds of the next grant being sent. A role is proved at teardown by the seeded people
    # it holds, so an unapplied grant leaves an empty role that teardown, rightly, refuses to claim.
    # So the step waits until every grant it sent is visible, sending the missing ones again every
    # thirty seconds - adding somebody already in a role changes nothing - for up to four minutes.
    $pendingGrants = 0
    if ($grantedTo.Count -gt 0 -and -not $WhatIfPreference) {
        # Counted in attempts rather than against the clock, so it is the same time live and a
        # deterministic loop under a test that mocks the sleep. Four minutes, because a live seed once waited more than two.
        $attempt = 0
        while ($true) {
            $attempt++
            $visible = @{}
            foreach ($role in @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $connection)) {
                if ($null -ne $role -and $grantedTo.ContainsKey([string]$role.id)) { $visible[[string]$role.id] = @($role.users | ForEach-Object { [string]$_ }) }
            }
            $pendingGrants = 0
            $missingByRole = @{}
            foreach ($roleId in $grantedTo.Keys) {
                $absent = @($grantedTo[$roleId] | Where-Object { @($visible[$roleId]) -notcontains $_ })
                if ($absent.Count -gt 0) { $missingByRole[$roleId] = $absent }
                $pendingGrants += $absent.Count
            }
            if ($pendingGrants -eq 0 -or $attempt -ge 48) { break }

            if ($attempt % 6 -eq 0) {
                foreach ($roleId in $missingByRole.Keys) {
                    Write-Verbose "Sending $($missingByRole[$roleId].Count) role grant(s) to role $roleId again; OneLogin has not applied them"
                    try {
                        $null = Invoke-OneLoginRequest -Method POST -Path "roles/$roleId/users" -Body ('[{0}]' -f ($missingByRole[$roleId] -join ',')) -Connection $connection
                    }
                    catch {
                        Write-Verbose "Sending the role grants to role $roleId again failed: $($_.Exception.Message)"
                    }
                }
            }
            Start-Sleep -Seconds 5
        }
        if ($pendingGrants -gt 0) {
            # Formatted as one string first: -f binds tighter than +.
            $template = 'OneLogin has not yet shown {0} of the role grants it accepted. They usually appear within seconds; until they do, ' +
                'verification reports them missing and teardown cannot prove the roles they are in.'
            Write-Warning ($template -f $pendingGrants)
        }
    }

    # OneLogin approves a person only while the account has a user licence for them, and otherwise
    # makes them Unlicensed without an error - the create answers with the approved state it was
    # asked for. An unlicensed person cannot hold a role, so their role grants are dropped too.
    # Read back once, so the seed says what happened rather than leaving it to verification.
    if (($created.Count + $updated) -gt 0 -and -not $WhatIfPreference) {
        $approved = $script:OneLoginUserState['Approved']
        $wanted = @{}
        foreach ($row in $rows) { if ($script:OneLoginUserState[$row.State] -eq $approved) { $wanted[(Resolve-OneLoginSeedName -Key $row.Key -Kind Username -Connection $connection)] = $true } }
        $unlicensed = @(Get-OneLoginSeededObject -Type Users -Connection $connection | Where-Object {
                $wanted.ContainsKey(([string]$_.username).ToLowerInvariant()) -and [int]$_.state -eq $script:OneLoginUserState['Unlicensed']
            } | ForEach-Object { [string]$_.username } | Sort-Object)
        if ($unlicensed.Count -gt 0) {
            $shown = @($unlicensed | Select-Object -First 5) -join ', '
            if ($unlicensed.Count -gt 5) { $shown = '{0}, ...' -f $shown }
            # Built before it is added: inside a method call's parentheses the commas after -f
            # would be read as more arguments to Add, and the format would be one value short.
            $template = '{0} person(s) the data approves were made Unlicensed by OneLogin, which means the account has no user licence left ' +
                'for them. They exist, but hold no roles: {1}'
            $message = $template -f $unlicensed.Count, $shown
            $errors.Add($message)
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalUsers         = @($rows).Count
            CreatedUsers       = $created.Count
            ReusedUsers        = $reused.Count
            UpdatedUsers       = $updated
            ManagersSet        = $managersSet
            UsersLocked        = $lockedCount
            MembershipsApplied = $membershipsApplied
            GrantsNotYetShown  = $pendingGrants
            Users              = (@($created) + @($reused))
            Errors             = $errors.ToArray()
        }
    }
}
