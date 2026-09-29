function New-OneLoginPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded user security policies and attaches each to seeded groups only
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $scope = if ($Tier) { Get-OneLoginSeedScope -Tier $Tier } else { Get-OneLoginSeedScope }
    $dataPath = Get-OneLoginDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginPolicies.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $groupNameByKey = @{}
    foreach ($groupRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginGroups.csv') -Encoding UTF8)) {
        $groupNameByKey[$groupRow.Key] = Resolve-OneLoginSeedName -Key $groupRow.Name -Kind DisplayName -Connection $connection
    }

    # Groups the seed may attach a policy to: its own, or an empty one of its names. A policy is never
    # attached to a group holding anybody else, because it would then govern how they sign in.
    $ownedUserId = @(Get-OneLoginSeededObject -Type Users -Connection $connection | ForEach-Object { [string]$_.id })
    $groupByName = @{}
    foreach ($group in @(Get-OneLoginSeededObject -Type Groups -AllowEmpty -OwnedUserId $ownedUserId -Connection $connection)) {
        $groupByName[[string]$group.name] = $group
    }
    $usableGroupId = @($groupByName.Values | ForEach-Object { [string]$_.id })

    $byName = @{}
    foreach ($policy in @(Invoke-OneLoginRequest -Method GET -Path 'policies' -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })) {
        $byName[[string]$policy.name] = $policy
    }
    $usable = @{}
    foreach ($policy in @(Get-OneLoginSeededObject -Type Policies -AllowEmpty -OwnedUserId $ownedUserId -OwnedGroupId $usableGroupId -Connection $connection)) {
        $usable[[string]$policy.id] = $true
    }

    # The settings the data can carry, by column and by OneLogin field. Nothing else about a policy
    # is written; in particular is_default is never sent.
    $settingField = [ordered]@{
        MinimumPasswordLength       = 'minimum_password_length'
        PasswordExpirationDays      = 'password_expiration_days'
        PasswordsRemembered         = 'passwords_remembered'
        MaximumInvalidLoginAttempts = 'maximum_invalid_login_attempts'
        LockEffectiveMinutes        = 'lock_effective_minutes'
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $settingsUpdated = 0
    $attached = 0

    foreach ($row in $rows) {
        $groupKeys = @(([string]$row.Groups -split ';') | Where-Object { $_ -and $scope.Groups.Contains($_) })
        if ($groupKeys.Count -eq 0) {
            # Proved only by the seeded groups using it, so a policy no group in the tiers will use
            # could never be claimed. Not made rather than made and stranded.
            Write-Verbose "Policy $($row.Key) has no group in the tiers being seeded; not creating it"
            $skipped.Add($row.Key)
            continue
        }

        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $settings = [ordered]@{}
        foreach ($column in $settingField.Keys) { if ($row.$column) { $settings[$settingField[$column]] = [int]$row.$column } }

        $policy = $null
        if ($byName.ContainsKey($name)) {
            $policy = $byName[$name]
            if (-not $usable.ContainsKey([string]$policy.id)) {
                $errors.Add("Policy '$name' already exists and is the default, or is used by groups this module did not seed. It is left alone and attached to nothing.")
                continue
            }
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $policy.id })

            # Put its settings back as the data describes.
            $current = Invoke-OneLoginRequest -Method GET -Path "policies/$($policy.id)" -Connection $connection
            $change = [ordered]@{}
            foreach ($field in $settings.Keys) { if ([string]$current.$field -ne [string]$settings[$field]) { $change[$field] = $settings[$field] } }
            if ($change.Count -gt 0 -and $PSCmdlet.ShouldProcess($name, ('Update OneLogin policy ({0})' -f (@($change.Keys) -join ', ')))) {
                try {
                    $null = Invoke-OneLoginRequest -Method PUT -Path "policies/$($policy.id)" -Body $change -Connection $connection
                    $settingsUpdated++
                }
                catch { $errors.Add("Could not update policy ${name}: $($_.Exception.Message)") }
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin user policy')) { continue }
            $body = [ordered]@{ name = $name; kind = 'user' }
            foreach ($field in $settings.Keys) { $body[$field] = $settings[$field] }
            try {
                $policy = Invoke-OneLoginRequest -Method POST -Path 'policies' -Body $body -Connection $connection
                $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $policy.id })
                Write-Verbose "Created policy $name"
            }
            catch {
                $errors.Add("Could not create policy ${name}: $($_.Exception.Message)")
                Write-Warning "Could not create policy ${name}: $($_.Exception.Message)"
                continue
            }
        }

        foreach ($groupKey in $groupKeys) {
            $group = $groupByName[$groupNameByKey[$groupKey]]
            if (-not $group) {
                $errors.Add("Group '$groupKey' for policy $name does not exist, or is not one the seed may use; run New-OneLoginGroup first")
                continue
            }
            if ([string]$group.policy_id -eq [string]$policy.id) { continue }
            if (-not $PSCmdlet.ShouldProcess("$($group.name) <- $name", 'Attach OneLogin policy to group')) { continue }
            try {
                $null = Invoke-OneLoginRequest -Method PUT -Path "groups/$($group.id)" -Body @{ policy_id = [long]$policy.id } -Connection $connection
                $attached++
            }
            catch { $errors.Add("Could not attach policy $name to group $($group.name): $($_.Exception.Message)") }
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalPolicies    = @($rows).Count
            CreatedPolicies  = $created.Count
            ReusedPolicies   = $reused.Count
            SkippedPolicies  = $skipped.ToArray()
            SettingsUpdated  = $settingsUpdated
            GroupsAttached   = $attached
            Policies         = (@($created) + @($reused))
            Errors           = $errors.ToArray()
        }
    }
}
