function New-OneLoginAppRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded app rules, which hand a seeded app's groups claim out by seeded role
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

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginAppRules.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $appNameByKey = @{}
    foreach ($appRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginApps.csv') -Encoding UTF8)) {
        $appNameByKey[$appRow.Key] = Resolve-OneLoginSeedName -Key $appRow.Name -Kind DisplayName -Connection $connection
    }
    $roleNameByKey = @{}
    foreach ($roleRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginRoles.csv') -Encoding UTF8)) {
        $roleNameByKey[$roleRow.Key] = Resolve-OneLoginSeedName -Key $roleRow.Name -Kind DisplayName -Connection $connection
    }

    # A rule goes on a proved seeded app and names a role the seed may use. A rule naming somebody
    # else's role would hand their holders a claim on a seeded app; one on somebody else's app would
    # change what that app gives its real users.
    $appByName = @{}
    foreach ($app in @(Get-OneLoginSeededObject -Type Apps -Connection $connection)) { $appByName[[string]$app.name] = $app }
    $roleByName = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -Connection $connection)) { $roleByName[[string]$role.name] = $role }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $rulesByApp = @{}

    foreach ($row in $rows) {
        if (-not $scope.Roles.Contains($row.Role)) {
            Write-Verbose "App rule $($row.Key) names role $($row.Role), which the tiers being seeded do not create; not creating it"
            $skipped.Add($row.Key)
            continue
        }

        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $app = $appByName[$appNameByKey[$row.App]]
        $role = $roleByName[$roleNameByKey[$row.Role]]
        if (-not $app) { $errors.Add("App '$($row.App)' for app rule $name does not exist, or is not seeded; run New-OneLoginApp first"); continue }
        if (-not $role) { $errors.Add("Role '$($row.Role)' for app rule $name does not exist, or is not one the seed may use; run New-OneLoginRole first"); continue }

        if (-not $rulesByApp.ContainsKey([string]$app.id)) {
            $rules = @{}
            foreach ($query in @($null, @{ enabled = 'false' })) {
                $arguments = @{ Method = 'GET'; Path = "apps/$($app.id)/rules"; Connection = $connection }
                if ($query) { $arguments['Query'] = $query }
                foreach ($rule in @(Invoke-OneLoginRequest @arguments | ForEach-Object { $_ } | Where-Object { $null -ne $_ })) { $rules[[string]$rule.name] = $rule }
            }
            $rulesByApp[[string]$app.id] = $rules
        }

        if ($rulesByApp[[string]$app.id].ContainsKey($name)) {
            Write-Verbose "App rule $name already exists on $($app.name); reusing it"
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $rulesByApp[[string]$app.id][$name].id; AppId = $app.id })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$($app.name) : $name", 'Create OneLogin app rule')) { continue }

        # The action is the provider's, not the data's: set the OIDC groups claim from member_of,
        # which on a seeded person names only seeded groups in the lab domain.
        $body = @{
            name       = $name
            match      = 'all'
            enabled    = [bool]::Parse($row.Enabled)
            conditions = @(@{ source = 'has_role'; operator = $row.Operator; value = [string]$role.id })
            actions    = @(@{ action = 'set_groups'; value = @('member_of'); expression = $row.Expression })
        }
        try {
            $result = Invoke-OneLoginRequest -Method POST -Path "apps/$($app.id)/rules" -Body $body -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id; AppId = $app.id })
            Write-Verbose "Created app rule $name on $($app.name)"
        }
        catch {
            $errors.Add("Could not create app rule $name on $($app.name): $($_.Exception.Message)")
            Write-Warning "Could not create app rule $name on $($app.name): $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalAppRules   = @($rows).Count
            CreatedAppRules = $created.Count
            ReusedAppRules  = $reused.Count
            SkippedAppRules = $skipped.ToArray()
            AppRules        = (@($created) + @($reused))
            Errors          = $errors.ToArray()
        }
    }
}
