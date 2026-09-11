function New-FreeIPASudoRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded sudo commands, command groups and rules from Data\FreeIPASudoCommands.csv and Data\FreeIPASudoRules.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RuleName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $dataPath = Get-FreeIPADataPath

    $commandRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPASudoCommands.csv') -Encoding UTF8)
    $rulePath = Join-Path -Path $dataPath -ChildPath 'FreeIPASudoRules.csv'
    $ruleRows = @(Import-Csv -Path $rulePath -Encoding UTF8)
    if ($RuleName) {
        $ruleRows = @($ruleRows | Where-Object { $RuleName -contains $_.Name })
        $unknown = @($RuleName | Where-Object { $ruleRows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $rulePath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules           = $ruleRows.Count
        CreatedRules         = 0
        UpdatedRules         = 0
        CommandsCreated      = 0
        CommandsReused       = 0
        CommandGroupsCreated = 0
        MembershipsApplied   = 0
        Rules                = @()
        Errors               = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }
    $describe = { param($text) ('{0} {1}' -f $text, $marker.Marker).Trim() }
    $record = { param($problem) $result.Errors += $problem; Write-Error $problem }

    $existingCommands = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type SudoCommands -Connection $connection)) { $existingCommands[[string](@($entry.sudocmd)[0])] = $entry }
    $existingGroups = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type SudoCommandGroups -Connection $connection)) { $existingGroups[[string](@($entry.cn)[0])] = $entry }
    $existingRules = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type SudoRules -Connection $connection)) { $existingRules[[string](@($entry.cn)[0])] = $entry }

    # --- Commands -------------------------------------------------------------------------------
    # A command that exists without the marker belongs to the realm: reused, never modified.
    foreach ($row in ($commandRows | Where-Object Kind -eq 'Command')) {
        $path = $row.Name
        if (-not $PSCmdlet.ShouldProcess($path, 'Create FreeIPA sudo command')) { continue }
        try {
            if ($existingCommands.ContainsKey($path)) {
                $null = Invoke-FreeIPARequest -Method 'sudocmd_mod' -Arguments $path -Options @{ description = & $describe $row.Description } -Connection $connection -IgnoreError 'EmptyModlist'
                continue
            }
            $shown = Invoke-FreeIPARequest -Method 'sudocmd_show' -Arguments $path -Connection $connection -IgnoreError 'NotFound'
            if ($shown) {
                $result.CommandsReused++
                Write-Verbose "Sudo command $path already exists in the realm and is reused as it is"
                continue
            }
            $null = Invoke-FreeIPARequest -Method 'sudocmd_add' -Arguments $path -Options @{ description = & $describe $row.Description } -Connection $connection
            $result.CommandsCreated++
        }
        catch { & $record "Failed to create sudo command '$path': $($_.Exception.Message)" }
    }

    foreach ($row in ($commandRows | Where-Object Kind -eq 'Group')) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA sudo command group')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($existingGroups.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'sudocmdgroup_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'sudocmdgroup_add' -Arguments $name -Options $options -Connection $connection
                $result.CommandGroupsCreated++
            }
            $outcome = Add-FreeIPAMember -Method 'sudocmdgroup_add_member' -Name $name -Members @{ sudocmd = @(& $split $row.Members) } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }
        }
        catch { & $record "Failed to create sudo command group '$name': $($_.Exception.Message)" }
    }

    # --- Rules ----------------------------------------------------------------------------------
    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $ruleRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA sudo rule')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($row.Order -match '^\d+$') { $options['sudoorder'] = [int]$row.Order }
            if ($row.UserCategory) { $options['usercategory'] = $row.UserCategory }
            if ($row.HostCategory) { $options['hostcategory'] = $row.HostCategory }
            if ($row.CommandCategory) { $options['cmdcategory'] = $row.CommandCategory }
            if ($row.RunAsUserCategory) { $options['ipasudorunasusercategory'] = $row.RunAsUserCategory }

            if ($existingRules.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'sudorule_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedRules++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'sudorule_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedRules++
                Write-Verbose "Created sudo rule $name"
            }

            $clauses = @(
                @{ Method = 'sudorule_add_user'; Members = @{ user = @(& $split $row.Users); group = @(& $resolve $row.Groups 'Name') } }
                @{ Method = 'sudorule_add_host'; Members = @{ host = @(& $resolve $row.Hosts 'Host'); hostgroup = @(& $resolve $row.Hostgroups 'Name') } }
                @{ Method = 'sudorule_add_allow_command'; Members = @{ sudocmd = @(& $split $row.AllowCommands); sudocmdgroup = @(& $resolve $row.AllowCommandGroups 'Name') } }
                @{ Method = 'sudorule_add_deny_command'; Members = @{ sudocmd = @(& $split $row.DenyCommands) } }
                @{ Method = 'sudorule_add_runasuser'; Members = @{ user = @(& $split $row.RunAsUsers) } }
            )
            foreach ($clause in $clauses) {
                $outcome = Add-FreeIPAMember -Method $clause.Method -Name $name -Members $clause.Members -Connection $connection
                $result.MembershipsApplied += $outcome.Completed
                foreach ($problem in $outcome.Errors) { & $record $problem }
            }

            foreach ($option in (& $split $row.Options)) {
                $null = Invoke-FreeIPARequest -Method 'sudorule_add_option' -Arguments $name -Options @{ ipasudoopt = $option } -Connection $connection -IgnoreError 'DuplicateEntry'
            }

            if ($row.Enabled -eq 'FALSE') {
                $null = Invoke-FreeIPARequest -Method 'sudorule_disable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyInactive'
            }
            elseif ($existingRules.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'sudorule_enable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyActive'
            }

            $rules.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Enabled = ($row.Enabled -ne 'FALSE'); Order = $row.Order })
        }
        catch { & $record "Failed to create sudo rule '$name': $($_.Exception.Message)" }
    }

    $result.Rules = $rules.ToArray()
    Write-Verbose "Sudo: $($result.CreatedRules) rules created, $($result.UpdatedRules) updated, $($result.CommandsCreated) commands created, $($result.CommandsReused) reused, $($result.CommandGroupsCreated) groups, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
