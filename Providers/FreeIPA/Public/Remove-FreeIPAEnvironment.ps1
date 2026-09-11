function Remove-FreeIPAEnvironment {
    <#
    .SYNOPSIS
        Removes everything the seed created, proving ownership of each object first

    .DESCRIPTION
        Tears down in the reverse of the order the seed built: the delegation rules and
        targets and the services, the password policies, the roles, privileges and
        permissions, the sudo rules, command groups and tagged commands, the HBAC rules,
        service groups and services, the netgroups, then hosts, host groups, users in every
        lifecycle state, and groups deepest first. Nothing is deleted for merely carrying the
        prefix. Each type has to satisfy the evidence the seed wrote - the tag in a user's or
        host's userclass, the marker in a description, a policy's group being seeded - and
        Get-FreeIPASeededObject is the one place that evidence is judged. A sudo command that
        existed before the seed, without the marker, is left behind; so is any stock rule,
        service or privilege a seeded object referenced.

        Deletes go to the server in batches, because FreeIPA takes a list of names per delete
        and a run of four hundred hosts one at a time is a run of four hundred round trips.
        Each object is still confirmed on its own, which is what keeps -WhatIf listing every
        one by name. A private group goes with its user, and a managed netgroup with its host
        group, because FreeIPA removes those itself.

        The automation service account is a seeded user and is the one that must not be
        deleted while it is the credential in use, so it is kept unless -RemoveServiceAccount
        is passed, and then removed last. Its credential record goes with it only under
        -RemoveCredentialFile, and the vault secret the record names is read before the file
        is deleted, or the secret is orphaned.

        -WhatIf wins over -Force. -Force suppresses the prompts by setting the confirm
        preference rather than by bypassing ShouldProcess, so ShouldProcess still runs and
        still returns false under -WhatIf. That distinction is pinned by the tests because
        -Force defeating -WhatIf was the worst defect an earlier module shipped.

    .PARAMETER Keep
        Object types to leave in place: Services, PasswordPolicies, Roles, SudoRules, HbacRules,
        Netgroups, Hosts, Hostgroups, Users, Groups.

    .PARAMETER RemoveServiceAccount
        Also delete the automation service account. It is removed last, after everything it
        was used to remove.

    .PARAMETER RemoveCredentialFile
        With -RemoveServiceAccount, also delete the credential record and the vault secret it
        names.

    .PARAMETER Force
        Do not prompt. Has no effect under -WhatIf.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with BaseUrl, Prefix, StartTime, EndTime and a Removed and Errors list
        per object type.

    .EXAMPLE
        PS> Remove-FreeIPAEnvironment -WhatIf

        DESCRIPTION: Lists everything that would be removed
        OUTPUT: One WhatIf line per object the module can prove it owns
        USE CASE: Always the first teardown call

    .EXAMPLE
        PS> Remove-FreeIPAEnvironment -Keep Groups -Force -PassThru

        DESCRIPTION: Removes everything except the groups, without prompting
        OUTPUT: The result object with counts per type
        USE CASE: Re-seeding users against groups a report was already written against

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The teardown summary is written for the person watching; the result object carries the same data.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'attribute',
        Justification = 'Read inside the name-of script block the sweep is handed, which the analyzer does not follow.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Services', 'PasswordPolicies', 'Roles', 'SudoRules', 'HbacRules', 'Netgroups', 'Hosts', 'Hostgroups',
            'Users', 'Groups')]
        [string[]]$Keep = @(),

        [Parameter()]
        [switch]$RemoveServiceAccount,

        [Parameter()]
        [switch]$RemoveCredentialFile,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $results = [PSCustomObject]@{
        BaseUrl        = $connection.BaseUrl
        Prefix         = $connection.Prefix
        StartTime      = Get-Date
        EndTime          = $null
        Services         = @{ Removed = @(); Errors = @() }
        PasswordPolicies = @{ Removed = @(); Errors = @() }
        Roles            = @{ Removed = @(); Errors = @() }
        SudoRules        = @{ Removed = @(); Errors = @() }
        HbacRules        = @{ Removed = @(); Errors = @() }
        Netgroups        = @{ Removed = @(); Errors = @() }
        Hosts            = @{ Removed = @(); Errors = @() }
        Hostgroups       = @{ Removed = @(); Errors = @() }
        Users            = @{ Removed = @(); Errors = @() }
        Groups           = @{ Removed = @(); Errors = @() }
        ServiceAccount   = @{ Removed = @(); Errors = @() }
    }

    Write-TestMessage -Message "FreeIPA Test Environment Teardown ($($connection.BaseUrl))" -Type Header

    # Read directly rather than through ShouldProcess alone, so -Force can skip the prompt
    # without also skipping the preview.
    $isWhatIf = $WhatIfPreference

    # -Force sets the preference rather than short-circuiting ShouldProcess, which is what
    # keeps -WhatIf working: ShouldProcess is still called and still returns false under it.
    if ($Force -and -not $isWhatIf) {
        $ConfirmPreference = 'None'
    }

    if (-not $Force -and -not $isWhatIf) {
        $prompt = ("This permanently deletes every service, delegation rule, password policy, role, privilege, permission, " +
            "sudo rule, HBAC rule, netgroup, host, host group, user and group tagged '$($marker.Tag)' " +
            "in $($connection.BaseUrl), including preserved and staged users. FreeIPA has no undo.")
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Remove FreeIPA test environment')) {
            Write-TestMessage -Message 'Teardown cancelled.' -Type Warning
            if ($PassThru) { return $results }
            return
        }
    }

    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { [string]$value } }

    # A sweep is: confirm each object by name, then delete the confirmed ones in batches of
    # fifty with 'continue', so one refusal does not abandon the batch, and record what the
    # server says it could not do.
    $sweep = {
        param($key, $label, $one, $items, $nameOf, $method, $extraOptions)
        Write-TestMessage -Message "Removing $label" -Type Info
        $approved = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $items) {
            $name = & $nameOf $item
            if ($PSCmdlet.ShouldProcess($name, "Delete FreeIPA $one")) { $approved.Add($name) }
        }
        for ($start = 0; $start -lt $approved.Count; $start += 50) {
            $chunk = @($approved[$start..([Math]::Min($start + 49, $approved.Count - 1))])
            $options = @{ continue = $true }
            if ($extraOptions) { foreach ($k in $extraOptions.Keys) { $options[$k] = $extraOptions[$k] } }
            try {
                $outcome = Invoke-FreeIPARequest -Method $method -Arguments $chunk -Options $options -Connection $connection
                $failed = @{}
                if ($outcome -and $outcome.result -and $outcome.result.PSObject.Properties['failed']) {
                    foreach ($failure in @($outcome.result.failed)) {
                        $text = [string]$failure
                        $failedName = ($text -split ':', 2)[0].Trim()
                        $failed[$failedName] = $text
                    }
                }
                foreach ($name in $chunk) {
                    if ($failed.ContainsKey($name)) {
                        $results.$key.Errors += $failed[$name]
                        Write-Error "Failed to delete '$name': $($failed[$name])"
                    }
                    else { $results.$key.Removed += $name }
                }
            }
            catch {
                foreach ($name in $chunk) { $results.$key.Errors += "${name}: $($_.Exception.Message)" }
                Write-Error "Failed to delete a batch of $($chunk.Count) $label`: $($_.Exception.Message)"
            }
        }
    }

    # A type whose objects are found by one discovery call and deleted by one method, with
    # the name in a given attribute. The access layers are all this shape.
    $sweepType = {
        param($key, $type, $label, $one, $method, $attribute, $extraOptions)
        try {
            $items = @(Get-FreeIPASeededObject -Type $type -Connection $connection)
            & $sweep $key $label $one $items { param($i) & $first $i.$attribute } $method $extraOptions
        }
        catch {
            $results.$key.Errors += $_.Exception.Message
            Write-Error "Could not enumerate ${label}: $($_.Exception.Message)"
        }
    }

    # --- 1. The access layers, each in the reverse of the order it was built ----------------
    # A service goes before its host; a delegation rule before the target it names. A policy
    # goes before its group. A role before its privileges, and those before their permissions.
    # A rule before the command group it allows, and a command only when the seed made it.
    if ('Services' -notin $Keep) {
        & $sweepType 'Services' 'ServiceDelegationRules' 'service delegation rules' 'service delegation rule' 'servicedelegationrule_del' 'cn' $null
        & $sweepType 'Services' 'ServiceDelegationTargets' 'service delegation targets' 'service delegation target' 'servicedelegationtarget_del' 'cn' $null
        & $sweepType 'Services' 'Services' 'services' 'service' 'service_del' 'krbcanonicalname' $null
    }
    if ('PasswordPolicies' -notin $Keep) {
        & $sweepType 'PasswordPolicies' 'PasswordPolicies' 'password policies' 'password policy' 'pwpolicy_del' 'cn' $null
    }
    if ('Roles' -notin $Keep) {
        & $sweepType 'Roles' 'Roles' 'roles' 'role' 'role_del' 'cn' $null
        & $sweepType 'Roles' 'Privileges' 'privileges' 'privilege' 'privilege_del' 'cn' $null
        & $sweepType 'Roles' 'Permissions' 'permissions' 'permission' 'permission_del' 'cn' $null
    }
    if ('SudoRules' -notin $Keep) {
        & $sweepType 'SudoRules' 'SudoRules' 'sudo rules' 'sudo rule' 'sudorule_del' 'cn' $null
        & $sweepType 'SudoRules' 'SudoCommandGroups' 'sudo command groups' 'sudo command group' 'sudocmdgroup_del' 'cn' $null
        & $sweepType 'SudoRules' 'SudoCommands' 'sudo commands the seed made' 'sudo command' 'sudocmd_del' 'sudocmd' $null
    }
    if ('HbacRules' -notin $Keep) {
        & $sweepType 'HbacRules' 'HbacRules' 'HBAC rules' 'HBAC rule' 'hbacrule_del' 'cn' $null
        & $sweepType 'HbacRules' 'HbacServiceGroups' 'HBAC service groups' 'HBAC service group' 'hbacsvcgroup_del' 'cn' $null
        & $sweepType 'HbacRules' 'HbacServices' 'HBAC services' 'HBAC service' 'hbacsvc_del' 'cn' $null
    }
    if ('Netgroups' -notin $Keep) {
        & $sweepType 'Netgroups' 'Netgroups' 'netgroups' 'netgroup' 'netgroup_del' 'cn' $null
    }

    # --- 2. Hosts, then host groups ---------------------------------------------------------
    if ('Hosts' -notin $Keep) {
        try {
            $hosts = @(Get-FreeIPASeededObject -Type Hosts -Connection $connection)
            & $sweep 'Hosts' 'hosts' 'host' $hosts { param($h) & $first $h.fqdn } 'host_del' @{ updatedns = $false }
        }
        catch {
            $results.Hosts.Errors += $_.Exception.Message
            Write-Error "Could not enumerate hosts: $($_.Exception.Message)"
        }
    }

    if ('Hostgroups' -notin $Keep) {
        try {
            $hostgroups = @(Get-FreeIPASeededObject -Type Hostgroups -Connection $connection)
            & $sweep 'Hostgroups' 'host groups' 'host group' $hostgroups { param($g) & $first $g.cn } 'hostgroup_del' $null
        }
        catch {
            $results.Hostgroups.Errors += $_.Exception.Message
            Write-Error "Could not enumerate host groups: $($_.Exception.Message)"
        }
    }

    # --- 3. Users in every state --------------------------------------------------------------
    # A preserved user is deleted for good by the same call that deleted it the first time; a
    # staged one lives in its own container and has its own call.
    if ('Users' -notin $Keep) {
        try {
            $users = @(Get-FreeIPASeededObject -Type Users -Connection $connection)
            & $sweep 'Users' 'users' 'user' $users { param($u) & $first $u.uid } 'user_del' $null
            $preserved = @(Get-FreeIPASeededObject -Type PreservedUsers -Connection $connection)
            & $sweep 'Users' 'preserved users' 'preserved user' $preserved { param($u) & $first $u.uid } 'user_del' $null
            $staged = @(Get-FreeIPASeededObject -Type StagedUsers -Connection $connection)
            & $sweep 'Users' 'staged users' 'staged user' $staged { param($u) & $first $u.uid } 'stageuser_del' $null
        }
        catch {
            $results.Users.Errors += $_.Exception.Message
            Write-Error "Could not enumerate users: $($_.Exception.Message)"
        }
    }

    # --- 4. Groups, deepest first -------------------------------------------------------------
    # A member group names its parents in memberof, so removing the leaves first leaves
    # nothing dangling if a deletion midway fails.
    if ('Groups' -notin $Keep) {
        try {
            $groups = @(Get-FreeIPASeededObject -Type Groups -Connection $connection)
            $seededNames = @{}
            foreach ($group in $groups) { $seededNames[(& $first $group.cn)] = $group }
            $depthOf = {
                param($group)
                $depth = 0
                $frontier = @()
                if ($group.PSObject.Properties['memberof_group']) { $frontier = @($group.memberof_group | Where-Object { $seededNames.ContainsKey([string]$_) }) }
                while ($frontier.Count -gt 0 -and $depth -lt 20) {
                    $depth++
                    $frontier = @($frontier | ForEach-Object {
                            $parent = $seededNames[[string]$_]
                            if ($parent.PSObject.Properties['memberof_group']) { @($parent.memberof_group | Where-Object { $seededNames.ContainsKey([string]$_) }) }
                        })
                }
                $depth
            }
            $ordered = @($groups | Sort-Object -Property @{ Expression = { & $depthOf $_ }; Descending = $true }, @{ Expression = { & $first $_.cn } })
            & $sweep 'Groups' 'groups' 'group' $ordered { param($g) & $first $g.cn } 'group_del' $null
        }
        catch {
            $results.Groups.Errors += $_.Exception.Message
            Write-Error "Could not enumerate groups: $($_.Exception.Message)"
        }
    }

    # --- 5. The service account, last ---------------------------------------------------------
    if ($RemoveServiceAccount) {
        try {
            $accountName = Get-FreeIPAServiceAccountName -Marker $marker
            $account = @(Get-FreeIPASeededObject -Type Users -IncludeServiceAccount -Connection $connection |
                    Where-Object { (& $first $_.uid) -eq $accountName })

            if ($connection.AuthType -eq 'ServiceAccount' -and $account.Count -gt 0) {
                Write-Warning "Removing the service account this session is connected as. Nothing else will work afterwards until you reconnect with a credential."
            }

            & $sweep 'ServiceAccount' 'the service account' 'service account' $account { param($u) & $first $u.uid } 'user_del' $null

            if ($RemoveCredentialFile) {
                $recordPath = Get-FreeIPACredentialPath -BaseUrl $connection.BaseUrl -Path $connection.CredentialPath
                if (Test-Path -LiteralPath $recordPath) {
                    if ($PSCmdlet.ShouldProcess($recordPath, 'Delete the service account credential record')) {
                        # The vault pointer is read before the file goes, or the secret is orphaned.
                        $record = $null
                        try { $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } catch { $record = $null }
                        if ($record -and $record.PSObject.Properties['secretName'] -and $record.secretName) {
                            try { Remove-TestVaultSecret -VaultName $record.vaultName -SecretName $record.secretName -Confirm:$false }
                            catch { Write-Warning "Could not remove the vault secret '$($record.secretName)': $($_.Exception.Message)" }
                        }
                        Remove-Item -LiteralPath $recordPath -Force
                        $results.ServiceAccount.Removed += $recordPath
                    }
                }
            }
        }
        catch {
            $results.ServiceAccount.Errors += $_.Exception.Message
            Write-Error "Could not remove the service account: $($_.Exception.Message)"
        }
    }

    $results.EndTime = Get-Date

    $tracked = @('Services', 'PasswordPolicies', 'Roles', 'SudoRules', 'HbacRules', 'Netgroups', 'Hosts', 'Hostgroups', 'Users', 'Groups', 'ServiceAccount')
    $removedCount = @($tracked | ForEach-Object { @($results.$_.Removed).Count } | Measure-Object -Sum).Sum
    $errorCount = @($tracked | ForEach-Object { @($results.$_.Errors).Count } | Measure-Object -Sum).Sum

    Write-TestMessage -Message 'Teardown Summary' -Type Header
    Write-Host "Objects removed: $removedCount" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Warning "Failures: $errorCount. Inspect the results object with -PassThru."
    }

    if ($PassThru) { return $results }
}
