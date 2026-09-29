function New-OneLoginSmartHook {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Smart Hook, always disabled and gated on a seeded role
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
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    $scope = if ($Tier) { Get-OneLoginSeedScope -Tier $Tier } else { Get-OneLoginSeedScope }
    $dataPath = Get-OneLoginDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginHooks.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $roleNameByKey = @{}
    foreach ($roleRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginRoles.csv') -Encoding UTF8)) {
        $roleNameByKey[$roleRow.Key] = Resolve-OneLoginSeedName -Key $roleRow.Name -Kind DisplayName -Connection $connection
    }
    $roleByName = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -Connection $connection)) { $roleByName[[string]$role.name] = $role }
    $usableRoleId = @($roleByName.Values | ForEach-Object { [string]$_.id })

    # The seeded hooks already there, found by the marker in their code.
    $ours = @(Get-OneLoginSeededObject -Type Hooks -OwnedRoleId $usableRoleId -Connection $connection)

    # The code. The marker line is what proves the hook ours; the handler changes nothing about a
    # sign-in - it hands back the policy the person already has.
    $code = ($script:OneLoginHookMarker -f $marker.Description) + "`n" +
        "exports.handler = async (context) => {`n  return { success: true, user: { policy_id: context.user.policy_id } };`n};`n"
    $function = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($code))

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $disabledAgain = 0

    foreach ($row in $rows) {
        if (-not $scope.Roles.Contains($row.Role)) {
            Write-Verbose "Hook $($row.Key) is gated on role $($row.Role), which the tiers being seeded do not create; not creating it"
            $skipped.Add($row.Key)
            continue
        }
        $role = $roleByName[$roleNameByKey[$row.Role]]
        if (-not $role) { $errors.Add("Role '$($row.Role)' for hook $($row.Key) does not exist, or is not one the seed may use; run New-OneLoginRole first"); continue }

        # Always disabled, and always gated on a seeded role, so that even if somebody enabled it, it
        # would run for seeded people and nobody else. Neither has a parameter.
        $body = [ordered]@{
            type       = $row.Type
            function   = $function
            disabled   = $true
            runtime    = 'nodejs22.x'
            retries    = 0
            timeout    = 1
            options    = @{ risk_enabled = $false; location_enabled = $false; mfa_device_info_enabled = $false }
            env_vars   = @()
            packages   = @{}
            conditions = @(@{ source = 'roles'; operator = '~'; value = [string]$role.id })
        }

        $existing = @($ours | Where-Object { [string]$_.type -eq [string]$row.Type })
        if ($existing) {
            $hook = $existing[0]
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Id = $hook.id; Type = $hook.type })
            if (-not $hook.disabled -and $PSCmdlet.ShouldProcess($hook.name, 'Disable OneLogin Smart Hook')) {
                # A seeded hook is never left enabled. Put back whole, because the endpoint replaces.
                try {
                    $null = Invoke-OneLoginRequest -Method PUT -Path "hooks/$($hook.id)" -Body $body -Connection $connection
                    $disabledAgain++
                }
                catch { $errors.Add("Could not disable the seeded $($row.Type) hook: $($_.Exception.Message)") }
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$($row.Type) hook gated on $($role.name)", 'Create OneLogin Smart Hook')) { continue }
        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'hooks' -Body $body -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Id = $result.id; Type = $row.Type })
            Write-Verbose "Created the $($row.Type) hook, disabled"
        }
        catch {
            # OneLogin allows one hook of a type per account; an account that already has its own is
            # left with it.
            $errors.Add("Could not create the $($row.Type) hook: $($_.Exception.Message). An account can hold one hook of a type; if it already has its own, pass -Skip Hooks.")
            Write-Warning "Could not create the $($row.Type) hook: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalHooks    = @($rows).Count
            CreatedHooks  = $created.Count
            ReusedHooks   = $reused.Count
            SkippedHooks  = $skipped.ToArray()
            DisabledAgain = $disabledAgain
            Hooks         = (@($created) + @($reused))
            Errors        = $errors.ToArray()
        }
    }
}
