function New-FreeIPAHbacRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded HBAC services, service groups and rules from Data\FreeIPAHbacServices.csv and Data\FreeIPAHbacRules.csv
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

    $serviceRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPAHbacServices.csv') -Encoding UTF8)
    $rulePath = Join-Path -Path $dataPath -ChildPath 'FreeIPAHbacRules.csv'
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
        ServicesCreated      = 0
        ServiceGroupsCreated = 0
        MembershipsApplied   = 0
        Rules                = @()
        Errors               = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }
    $describe = { param($text) ('{0} {1}' -f $text, $marker.Marker).Trim() }
    $record = { param($problem) $result.Errors += $problem; Write-Error $problem }

    $existingServices = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type HbacServices -Connection $connection)) { $existingServices[[string](@($entry.cn)[0])] = $entry }
    $existingGroups = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type HbacServiceGroups -Connection $connection)) { $existingGroups[[string](@($entry.cn)[0])] = $entry }
    $existingRules = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type HbacRules -Connection $connection)) { $existingRules[[string](@($entry.cn)[0])] = $entry }

    # --- Services, then service groups and their members ------------------------------------
    foreach ($row in ($serviceRows | Where-Object Kind -eq 'Service')) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA HBAC service')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($existingServices.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'hbacsvc_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'hbacsvc_add' -Arguments $name -Options $options -Connection $connection
                $result.ServicesCreated++
            }
        }
        catch { & $record "Failed to create HBAC service '$name': $($_.Exception.Message)" }
    }

    foreach ($row in ($serviceRows | Where-Object Kind -eq 'Group')) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA HBAC service group')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($existingGroups.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'hbacsvcgroup_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'hbacsvcgroup_add' -Arguments $name -Options $options -Connection $connection
                $result.ServiceGroupsCreated++
            }
            $outcome = Add-FreeIPAMember -Method 'hbacsvcgroup_add_member' -Name $name -Members @{ hbacsvc = @(& $resolve $row.Members 'Name') } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }
        }
        catch { & $record "Failed to create HBAC service group '$name': $($_.Exception.Message)" }
    }

    # --- Rules ----------------------------------------------------------------------------------
    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $ruleRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA HBAC rule')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($row.UserCategory) { $options['usercategory'] = $row.UserCategory }
            if ($row.HostCategory) { $options['hostcategory'] = $row.HostCategory }
            if ($row.ServiceCategory) { $options['servicecategory'] = $row.ServiceCategory }

            if ($existingRules.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'hbacrule_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedRules++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'hbacrule_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedRules++
                Write-Verbose "Created HBAC rule $name"
            }

            $clauses = @(
                @{ Method = 'hbacrule_add_user'; Members = @{ user = @(& $split $row.Users); group = @(& $resolve $row.Groups 'Name') } }
                @{ Method = 'hbacrule_add_host'; Members = @{ host = @(& $resolve $row.Hosts 'Host'); hostgroup = @(& $resolve $row.Hostgroups 'Name') } }
                @{ Method = 'hbacrule_add_service'; Members = @{ hbacsvc = @(& $resolve $row.Services 'Name'); hbacsvcgroup = @(& $resolve $row.ServiceGroups 'Name') } }
            )
            foreach ($clause in $clauses) {
                $outcome = Add-FreeIPAMember -Method $clause.Method -Name $name -Members $clause.Members -Connection $connection
                $result.MembershipsApplied += $outcome.Completed
                foreach ($problem in $outcome.Errors) { & $record $problem }
            }

            if ($row.Enabled -eq 'FALSE') {
                $null = Invoke-FreeIPARequest -Method 'hbacrule_disable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyInactive'
            }
            elseif ($existingRules.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'hbacrule_enable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyActive'
            }

            $rules.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Enabled = ($row.Enabled -ne 'FALSE') })
        }
        catch { & $record "Failed to create HBAC rule '$name': $($_.Exception.Message)" }
    }

    $result.Rules = $rules.ToArray()
    Write-Verbose "HBAC: $($result.CreatedRules) rules created, $($result.UpdatedRules) updated, $($result.ServicesCreated) services, $($result.ServiceGroupsCreated) service groups, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
