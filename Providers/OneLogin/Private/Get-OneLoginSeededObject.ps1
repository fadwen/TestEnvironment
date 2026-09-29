function Get-OneLoginSeededObject {
    <#
    .SYNOPSIS
        Returns the objects of one type that this module can prove it created

    .DESCRIPTION
        Teardown's only source of truth, and the verifier's and the report's. Nothing is deleted
        for merely matching a name, and this is where that promise is kept - which matters more
        here than anywhere, because a OneLogin account is as likely to be somebody's production
        directory as a lab.

        Proof differs by type, because OneLogin gives each type a different place to hold it:

        - A user needs the seed tag in the custom field the seed created AND the prefix on the
          username. The account is asked server-side for users whose field holds the tag, and
          each is then checked here, ordinally, so a server that matched loosely still cannot
          hand teardown somebody else. The field has to exist first: before the first seed and
          after teardown there is nothing to ask.
        - An app and an API authorization server need the tag in their description AND the
          prefix on their name; a self-registration profile the tag in its help text and the
          prefix on its name. Either alone is not proof: the tag can be pasted into a real
          object's description, and the prefix alone is the name matching this module refuses to do.
        - A role has nothing but a name, so it is proved by what it holds. It needs the prefix, no
          administrators, at least one user or app, and every user it holds must be a proved
          seeded user and every app a proved seeded app. A prefixed role holding one real person
          is refused. So is an empty one, because nothing about it says who made it.
        - A group is proved the same way by its members: the prefix, no administrators, at least
          one member, every member a proved seeded user, and either no security policy or a
          prefixed one that is not the account's default.
        - A user security policy has no description either, so it is proved by the groups that use
          it: the prefix, not the default, and used by at least one group and by proved seeded
          groups alone.
        - A mapping needs the prefix, match 'all', the seed-tag condition the seed always writes -
          so it can only ever have acted on seeded people - and only add_role actions, each naming
          proved roles.
        - An app rule needs to be on a proved seeded app, carry the prefix, and name only proved
          seeded roles in its conditions.
        - A Smart Hook has no name at all. It is proved by the marker line the seed writes at the top
          of its code, and by conditions that name only proved seeded roles - at least one of them,
          so even an enabled hook could never have run for anybody else.
        - A custom field needs to be declared by this provider's data AND carry the attribute
          prefix in its shortname.

        Roles, groups, policies, mappings, hooks and app rules depend on what they hold or name, so
        teardown proves them while those still exist. A mapping, hook or app rule naming a role that
        no longer exists at all is still accepted: a deleted role grants nothing to anybody, and
        refusing it would strand whatever a teardown that stopped halfway left behind. A role that
        exists and is somebody else's still disqualifies it. Role membership on OneLogin also
        settles a few seconds after it is written; a role proved in the same breath as the seed that
        filled it may briefly read as empty, and is then refused rather than guessed at.

        -Unproven returns the other side: objects carrying the prefix (or, for a hook, the marker)
        that failed their proof, with the reason, so teardown can say what it left alone instead of
        staying silent.

        -AllowEmpty is the seed's view rather than teardown's. A role, group or policy the seed made
        and has not filled or attached yet is empty, and the seed has to be able to reuse it; one
        that holds somebody else's people or has administrators it must not touch. So under
        -AllowEmpty an empty one counts, and everything else about the proof still applies.
        Teardown never passes it.

    .PARAMETER Type
        Which kind of object to return.

    .PARAMETER Unproven
        Return the prefixed objects of the type that could not be proved, with the reason, rather
        than the proved ones. Not for users and custom fields, which without their proof are simply
        not ours.

    .PARAMETER AllowEmpty
        Count an empty role, group or policy as the module's, for the seed steps that fill them.
        Never used by teardown.

    .PARAMETER OwnedUserId
        The ids of the proved seeded users, when the caller already has them. Proved here when
        omitted.

    .PARAMETER OwnedAppId
        The ids of the proved seeded apps, likewise.

    .PARAMETER OwnedRoleId
        The ids of the proved seeded roles, likewise.

    .PARAMETER OwnedGroupId
        The ids of the proved seeded groups, likewise.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        The OneLogin objects this module owns, of the requested type. Under -Unproven,
        PSCustomObjects with Type, Id, Name and Reason.

    .EXAMPLE
        PS> Get-OneLoginSeededObject -Type Roles

        DESCRIPTION: Lists the seeded roles, proved by what they hold
        OUTPUT: Role objects
        USE CASE: Called by Remove-OneLoginEnvironment and Get-OneLoginEnvironmentReport

    .EXAMPLE
        PS> Get-OneLoginSeededObject -Type Hooks -Unproven

        DESCRIPTION: Lists hooks carrying the seed marker that this module will not touch, and why
        OUTPUT: Type, Id, Name and Reason for each
        USE CASE: Teardown's summary of what it left alone

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Attributes', 'Users', 'Apps', 'Roles', 'Groups', 'Policies', 'Mappings', 'AppRules', 'Hooks', 'ApiAuthorizations', 'SelfRegistration')]
        [string]$Type,

        [Parameter()]
        [switch]$Unproven,

        [Parameter()]
        [switch]$AllowEmpty,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$OwnedUserId,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$OwnedAppId,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$OwnedRoleId,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$OwnedGroupId,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-OneLoginConnection }

    $marker = Get-OneLoginSeedMarker -Prefix $Connection.Prefix
    $tag = $marker.Tag
    $prefix = $marker.Prefix
    $attribute = $script:OneLoginSeedAttribute

    $hasPrefix = { param($name) ([string]$name).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
    $idSet = {
        param([string[]]$Ids)
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($id in @($Ids)) { if ($id) { $null = $set.Add([string]$id) } }
        return , $set
    }
    $refuse = {
        param($object, [string]$reason, [string]$name)
        if (-not $name) { $name = [string]$object.name }
        [PSCustomObject]@{ Type = $Type; Id = [string]$object.id; Name = $name; Reason = $reason }
    }
    # Every list endpoint that does not page answers a bare array, which Windows PowerShell's
    # ConvertFrom-Json hands back as one object; ForEach-Object unrolls it on both editions.
    $list = {
        param([string]$Path, [hashtable]$Query)
        $arguments = @{ Method = 'GET'; Path = $Path; Connection = $Connection }
        if ($Query) { $arguments['Query'] = $Query }
        @(Invoke-OneLoginRequest @arguments | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
    }

    if ($Unproven -and $Type -in 'Attributes', 'Users') {
        throw "-Unproven applies to every type but Users and Attributes. A user or field without its proof is simply not ours."
    }

    # The owned sets the relational types are proved against, computed here when not supplied.
    $needUsers = $Type -in 'Roles', 'Groups', 'Policies'
    $needApps = $Type -in 'Roles', 'AppRules'
    $needRoles = $Type -in 'Mappings', 'AppRules', 'Hooks'
    $needGroups = $Type -eq 'Policies'
    if ($needUsers -and -not $PSBoundParameters.ContainsKey('OwnedUserId')) {
        $OwnedUserId = @(Get-OneLoginSeededObject -Type Users -Connection $Connection | ForEach-Object { [string]$_.id })
    }
    if ($needApps -and -not $PSBoundParameters.ContainsKey('OwnedAppId')) {
        $OwnedAppId = @(Get-OneLoginSeededObject -Type Apps -Connection $Connection | ForEach-Object { [string]$_.id })
    }
    if ($needRoles -and -not $PSBoundParameters.ContainsKey('OwnedRoleId')) {
        $OwnedRoleId = @(Get-OneLoginSeededObject -Type Roles -Connection $Connection | ForEach-Object { [string]$_.id })
    }
    if ($needGroups -and -not $PSBoundParameters.ContainsKey('OwnedGroupId')) {
        $OwnedGroupId = @(Get-OneLoginSeededObject -Type Groups -OwnedUserId $OwnedUserId -Connection $Connection | ForEach-Object { [string]$_.id })
    }
    $ownedUsers = & $idSet $OwnedUserId
    $ownedApps = & $idSet $OwnedAppId
    $ownedRoles = & $idSet $OwnedRoleId
    $ownedGroups = & $idSet $OwnedGroupId

    # A role a mapping, hook or rule names is acceptable when it is seeded, or when it no longer exists
    # in the account at all. Only a role that exists and is not seeded disqualifies.
    $acceptableRole = { $true }
    if ($needRoles) {
        $existingRoles = & $idSet @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $Connection |
                Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })
        $acceptableRole = { param([string]$Id) $ownedRoles.Contains($Id) -or -not $existingRoles.Contains($Id) }.GetNewClosure()
    }

    switch ($Type) {
        'Attributes' {
            $declared = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginCustomAttributes.csv') -Encoding UTF8 |
                    ForEach-Object { [string]$_.Shortname })
            return @(& $list 'users/custom_attributes' | Where-Object {
                    $_.id -and $declared -ccontains [string]$_.shortname -and
                    ([string]$_.shortname).StartsWith($script:OneLoginAttributePrefix, [StringComparison]::Ordinal)
                })
        }

        'Users' {
            # The field first. Without it no user can carry the tag, and asking the users endpoint
            # to filter on a field that does not exist is a question with no good answer.
            if (-not @(& $list 'users/custom_attributes' | Where-Object { [string]$_.shortname -ceq $attribute })) { return @() }

            # The fields are named: the listing leaves custom_attributes out unless asked, and the
            # check below would then prove nobody.
            $query = @{ ('custom_attributes.{0}' -f $attribute) = $tag; fields = $script:OneLoginUserFields }
            return @(Invoke-OneLoginRequest -Method GET -Path 'users' -Query $query -Paginate -Connection $Connection |
                    Where-Object {
                        $null -ne $_ -and $_.id -and
                        (& $hasPrefix $_.username) -and
                        $_.custom_attributes -and
                        [string]::Equals([string]$_.custom_attributes.$attribute, $tag, [StringComparison]::Ordinal)
                    })
        }

        { $_ -in 'Apps', 'ApiAuthorizations' } {
            $path = if ($Type -eq 'Apps') { 'apps' } else { 'api_authorizations' }
            $candidates = @(Invoke-OneLoginRequest -Method GET -Path $path -Paginate -Connection $Connection |
                    Where-Object { $null -ne $_ -and $_.id -and (& $hasPrefix $_.name) })
            $proved = { param($object) ([string]$object.description).Contains($tag) }
            if ($Unproven) {
                return @($candidates | Where-Object { -not (& $proved $_) } |
                        ForEach-Object { & $refuse $_ 'The name carries the prefix but the description does not carry the seed tag' })
            }
            return @($candidates | Where-Object { & $proved $_ })
        }

        'SelfRegistration' {
            $result = New-Object System.Collections.Generic.List[object]
            $listed = Invoke-OneLoginRequest -Method GET -Path 'self_registration_profiles' -Connection $Connection
            foreach ($summary in @($listed.self_registration_profiles | Where-Object { $null -ne $_ })) {
                if (-not $summary.id -or -not (& $hasPrefix $summary.name)) { continue }
                # The listing may leave the help text out; the profile itself carries it.
                $detail = Invoke-OneLoginRequest -Method GET -Path "self_registration_profiles/$($summary.id)" -IgnoreStatus 404 -Connection $Connection
                $registration = if ($detail -and $detail.self_registration_profile) { $detail.self_registration_profile } else { $summary }
                $reason = $null
                if (-not ([string]$registration.helptext).Contains($tag)) { $reason = 'The name carries the prefix but the help text does not carry the seed tag' }
                if ($Unproven) { if ($reason) { $result.Add((& $refuse $registration $reason)) } }
                elseif (-not $reason) { $result.Add($registration) }
            }
            return $result.ToArray()
        }

        'Roles' {
            $result = New-Object System.Collections.Generic.List[object]
            foreach ($role in @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $Connection)) {
                if ($null -eq $role -or -not $role.id -or -not (& $hasPrefix $role.name)) { continue }

                $users = @($role.users | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
                $apps = @($role.apps | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
                $admins = @($role.admins | Where-Object { $null -ne $_ })

                $reason = $null
                if ($admins.Count -gt 0) { $reason = 'It has administrators, and the seed never gives a role one' }
                elseif ($users.Count + $apps.Count -eq 0) {
                    if (-not $AllowEmpty) {
                        $reason = 'It holds no users and no apps, so nothing about it says who made it. If it was seeded moments ago, ' +
                            'OneLogin may not be showing its members yet; run the teardown again in a minute'
                    }
                }
                elseif (@($users | Where-Object { -not $ownedUsers.Contains($_) }).Count -gt 0) {
                    $reason = 'It holds {0} user(s) that are not seeded' -f @($users | Where-Object { -not $ownedUsers.Contains($_) }).Count
                }
                elseif (@($apps | Where-Object { -not $ownedApps.Contains($_) }).Count -gt 0) {
                    $reason = 'It holds {0} app(s) that are not seeded' -f @($apps | Where-Object { -not $ownedApps.Contains($_) }).Count
                }

                if ($Unproven) { if ($reason) { $result.Add((& $refuse $role $reason)) } }
                elseif (-not $reason) { $result.Add($role) }
            }
            return $result.ToArray()
        }

        'Groups' {
            # The account's policies, so a group's policy can be judged by name and default flag.
            $policyById = @{}
            foreach ($policy in (& $list 'policies')) { $policyById[[string]$policy.id] = $policy }

            $result = New-Object System.Collections.Generic.List[object]
            foreach ($group in @(Invoke-OneLoginRequest -Method GET -Path 'groups' -Paginate -Connection $Connection)) {
                if ($null -eq $group -or -not $group.id -or -not (& $hasPrefix $group.name)) { continue }

                # The group itself, because the listing leaves its administrators out.
                $detail = Invoke-OneLoginRequest -Method GET -Path "groups/$($group.id)" -IgnoreStatus 404 -Connection $Connection
                if ($null -eq $detail) { continue }
                # Every member, asked of the users endpoint rather than read from the group, which
                # is the one listing that is guaranteed to include people this module did not make.
                $members = @(Invoke-OneLoginRequest -Method GET -Path 'users' -Query @{ group_id = [string]$group.id; fields = 'id' } `
                        -Paginate -Connection $Connection | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })
                $admins = @($detail.admins | Where-Object { $null -ne $_ })
                $policy = if ($detail.policy_id) { $policyById[[string]$detail.policy_id] } else { $null }

                $reason = $null
                if ($admins.Count -gt 0) { $reason = 'It has administrators, and the seed never gives a group one' }
                elseif ($detail.policy_id -and (-not $policy -or $policy.is_default -or -not (& $hasPrefix $policy.name))) {
                    $reason = 'It carries a security policy the seed did not make'
                }
                elseif ($members.Count -eq 0) {
                    if (-not $AllowEmpty) { $reason = 'It has no members, so nothing about it says who made it' }
                }
                elseif (@($members | Where-Object { -not $ownedUsers.Contains($_) }).Count -gt 0) {
                    $reason = 'It holds {0} user(s) that are not seeded' -f @($members | Where-Object { -not $ownedUsers.Contains($_) }).Count
                }

                if ($Unproven) { if ($reason) { $result.Add((& $refuse $group $reason)) } }
                elseif (-not $reason) {
                    $detail | Add-Member -NotePropertyName MemberIds -NotePropertyValue $members -Force
                    $result.Add($detail)
                }
            }
            return $result.ToArray()
        }

        'Policies' {
            # Which groups use each policy. A policy is proved by them, so every group in the
            # account is read, not only the seeded ones.
            $usedBy = @{}
            foreach ($group in @(Invoke-OneLoginRequest -Method GET -Path 'groups' -Paginate -Connection $Connection)) {
                if ($null -eq $group -or -not $group.policy_id) { continue }
                $key = [string]$group.policy_id
                if (-not $usedBy.ContainsKey($key)) { $usedBy[$key] = New-Object System.Collections.Generic.List[string] }
                $usedBy[$key].Add([string]$group.id)
            }

            $result = New-Object System.Collections.Generic.List[object]
            foreach ($policy in (& $list 'policies')) {
                if (-not $policy.id -or -not (& $hasPrefix $policy.name)) { continue }
                $groups = @()
                if ($usedBy.ContainsKey([string]$policy.id)) { $groups = @($usedBy[[string]$policy.id]) }

                $reason = $null
                if ($policy.is_default) { $reason = 'It is the account''s default policy' }
                elseif ([string]$policy.kind -and [string]$policy.kind -ne 'user') { $reason = "It is a $($policy.kind) policy, and the seed makes user policies only" }
                elseif ($groups.Count -eq 0) {
                    if (-not $AllowEmpty) { $reason = 'No group uses it, so nothing about it says who made it' }
                }
                elseif (@($groups | Where-Object { -not $ownedGroups.Contains($_) }).Count -gt 0) {
                    $reason = 'It is used by {0} group(s) that are not seeded' -f @($groups | Where-Object { -not $ownedGroups.Contains($_) }).Count
                }

                if ($Unproven) { if ($reason) { $result.Add((& $refuse $policy $reason)) } }
                elseif (-not $reason) {
                    $policy | Add-Member -NotePropertyName GroupIds -NotePropertyValue $groups -Force
                    $result.Add($policy)
                }
            }
            return $result.ToArray()
        }

        'Mappings' {
            # Enabled and disabled mappings are two listings; the endpoint returns only the enabled
            # ones unless asked, verified live.
            # Each wrapped before they are joined: a listing of one comes back as the object itself,
            # and one object plus another is not an array.
            $all = @(@(& $list 'mappings') + @(& $list 'mappings' @{ enabled = 'false' }))
            $seen = @{}
            $result = New-Object System.Collections.Generic.List[object]
            $source = 'custom_attribute_{0}' -f $attribute
            foreach ($mapping in $all) {
                if (-not $mapping.id -or $seen.ContainsKey([string]$mapping.id)) { continue }
                $seen[[string]$mapping.id] = $true
                if (-not (& $hasPrefix $mapping.name)) { continue }

                $conditions = @($mapping.conditions | Where-Object { $null -ne $_ })
                $actions = @($mapping.actions | Where-Object { $null -ne $_ })
                $gated = @($conditions | Where-Object {
                        [string]$_.source -ceq $source -and [string]$_.operator -eq '=' -and
                        [string]::Equals([string]$_.value, $tag, [StringComparison]::Ordinal)
                    }).Count -gt 0
                $roleIds = @($actions | ForEach-Object { @($_.value) } | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })

                $reason = $null
                if ([string]$mapping.match -ne 'all') { $reason = "It matches '$($mapping.match)' rather than all of its conditions" }
                elseif (-not $gated) { $reason = 'It has no condition requiring the seed tag, so it could act on anybody' }
                elseif ($actions.Count -eq 0) { $reason = 'It has no actions' }
                elseif (@($actions | Where-Object { [string]$_.action -ne 'add_role' }).Count -gt 0) { $reason = 'It does something other than add a role' }
                elseif (@($roleIds | Where-Object { -not (& $acceptableRole $_) }).Count -gt 0) { $reason = 'It adds a role that is not seeded' }

                if ($Unproven) { if ($reason) { $result.Add((& $refuse $mapping $reason)) } }
                elseif (-not $reason) { $result.Add($mapping) }
            }
            return $result.ToArray()
        }

        'AppRules' {
            # Only on apps this module proves: a rule on somebody else's app is somebody else's,
            # whatever it is called. Enabled and disabled rules are two listings, as with mappings.
            $result = New-Object System.Collections.Generic.List[object]
            foreach ($appId in @($ownedApps)) {
                $seen = @{}
                foreach ($rule in @(@(& $list "apps/$appId/rules") + @(& $list "apps/$appId/rules" @{ enabled = 'false' }))) {
                    if (-not $rule.id -or $seen.ContainsKey([string]$rule.id)) { continue }
                    $seen[[string]$rule.id] = $true
                    if (-not (& $hasPrefix $rule.name)) { continue }

                    $conditions = @($rule.conditions | Where-Object { $null -ne $_ })
                    $foreign = @($conditions | Where-Object { [string]$_.source -ne 'has_role' -or -not (& $acceptableRole ([string]$_.value)) })

                    $reason = $null
                    if ($conditions.Count -eq 0) { $reason = 'It has no conditions, so it applies to everybody the app serves' }
                    elseif ($foreign.Count -gt 0) { $reason = 'It has a condition that is not a seeded role' }

                    $rule | Add-Member -NotePropertyName AppId -NotePropertyValue $appId -Force
                    if ($Unproven) { if ($reason) { $result.Add((& $refuse $rule $reason)) } }
                    elseif (-not $reason) { $result.Add($rule) }
                }
            }
            return $result.ToArray()
        }

        'Hooks' {
            $line = $script:OneLoginHookMarker -f $marker.Description
            $result = New-Object System.Collections.Generic.List[object]
            foreach ($summary in (& $list 'hooks')) {
                if (-not $summary.id) { continue }
                # The hook itself, because the listing leaves its code out, and the code is where the
                # marker is.
                $hook = Invoke-OneLoginRequest -Method GET -Path "hooks/$($summary.id)" -IgnoreStatus 404 -Connection $Connection
                if ($null -eq $hook) { continue }
                $code = ''
                try { $code = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$hook.function)) }
                catch { Write-Verbose "Hook $($hook.id) has code that is not base64; it is not the seed's" }
                # The marker is the only thing a hook can carry, so a hook without it is not a
                # candidate at all, and is never named as one left alone.
                if (-not $code.StartsWith($line, [StringComparison]::Ordinal)) { continue }

                $conditions = @($hook.conditions | Where-Object { $null -ne $_ })
                $name = '{0} hook {1}' -f $hook.type, $hook.id
                $reason = $null
                if ($conditions.Count -eq 0) { $reason = 'It carries the seed marker but no conditions, so it could run for anybody' }
                elseif (@($conditions | Where-Object { [string]$_.source -ne 'roles' -or -not (& $acceptableRole ([string]$_.value)) }).Count -gt 0) {
                    $reason = 'It carries the seed marker but a condition that is not a seeded role'
                }

                $hook | Add-Member -NotePropertyName name -NotePropertyValue $name -Force
                if ($Unproven) { if ($reason) { $result.Add((& $refuse $hook $reason $name)) } }
                elseif (-not $reason) { $result.Add($hook) }
            }
            return $result.ToArray()
        }
    }
}
