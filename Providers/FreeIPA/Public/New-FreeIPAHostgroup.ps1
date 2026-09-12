function New-FreeIPAHostgroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded FreeIPA host groups, nested as Data\FreeIPAHostgroups.csv describes
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$HostgroupName,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAHostgroups.csv'
    $allRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $rows = $allRows

    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($HostgroupName) {
        $rows = @($allRows | Where-Object { $HostgroupName -contains $_.Name })
        $unknown = @($HostgroupName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $parentsOf = @{}
    foreach ($row in $allRows) { $parentsOf[$row.Name] = @($row.Parent -split ';' | Where-Object { $_ }) }
    $depthOf = {
        param($key)
        $depth = 0
        $frontier = @($parentsOf[$key])
        while ($frontier.Count -gt 0 -and $depth -lt 20) {
            $depth++
            $frontier = @($frontier | ForEach-Object { if ($parentsOf.ContainsKey($_)) { $parentsOf[$_] } })
        }
        $depth
    }
    $rows = @($rows | Sort-Object -Property @{ Expression = { & $depthOf $_.Name } }, Name)

    $result = [PSCustomObject]@{
        TotalHostgroups   = $rows.Count
        CreatedHostgroups = 0
        UpdatedHostgroups = 0
        NestingsApplied   = 0
        ManagersApplied   = 0
        Hostgroups        = @()
        Errors            = @()
    }

    $existing = @{}
    foreach ($hostgroup in (Get-FreeIPASeededObject -Type Hostgroups -Connection $connection)) {
        $existing[[string](@($hostgroup.cn)[0])] = $hostgroup
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $hostgroups = [System.Collections.Generic.List[object]]::new()
    $created = @{}
    $index = 0

    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        $index++
        Write-TestProgress -Activity 'Seeding host groups' -Status "$index of $($rows.Count): $name" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA host group')) { continue }

        try {
            $description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'hostgroup_mod' -Arguments $name -Connection $connection `
                    -Options @{ description = $description } -IgnoreError 'EmptyModlist'
                $result.UpdatedHostgroups++
                Write-Verbose "Updated host group $name"
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'hostgroup_add' -Arguments $name -Connection $connection `
                    -Options @{ description = $description }
                $result.CreatedHostgroups++
                Write-Verbose "Created host group $name"
            }

            $created[$row.Name] = $name
            $hostgroups.Add([PSCustomObject]@{
                    Key     = $row.Name
                    Name    = $name
                    Parents = @($parentsOf[$row.Name])
                })
        }
        catch {
            $message = "Failed to create host group '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-TestProgress -Activity 'Seeding host groups' -Completed -ShowProgress:$ShowProgress

    $childrenOf = @{}
    foreach ($row in $rows) {
        if (-not $created.ContainsKey($row.Name)) { continue }
        foreach ($parentKey in $parentsOf[$row.Name]) {
            $parentName = Resolve-FreeIPASeedName -Key $parentKey -Marker $marker -Connection $connection
            if (-not ($created.ContainsKey($parentKey) -or $existing.ContainsKey($parentName))) {
                Write-Warning "Host group '$($created[$row.Name])' names parent '$parentKey', which does not exist. Left unnested."
                continue
            }
            if (-not $childrenOf.ContainsKey($parentName)) { $childrenOf[$parentName] = [System.Collections.Generic.List[string]]::new() }
            $childrenOf[$parentName].Add($created[$row.Name])
        }
    }

    foreach ($parentName in ($childrenOf.Keys | Sort-Object)) {
        if (-not $PSCmdlet.ShouldProcess($parentName, "Nest $($childrenOf[$parentName].Count) member host group(s)")) { continue }
        try {
            $outcome = Invoke-FreeIPARequest -Method 'hostgroup_add_member' -Arguments $parentName -Connection $connection `
                -Options @{ hostgroup = [object[]]@($childrenOf[$parentName]) }
            $result.NestingsApplied += [int]$outcome.completed
            foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
                if ($failure -like '*already a member*') { continue }
                $message = "Could not nest under '$parentName': $failure"
                $result.Errors += $message
                Write-Error $message
            }
        }
        catch {
            $message = "Failed to nest under '$parentName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }


    # Member managers: the users and groups who may change the membership without being
    # administrators. Applied after every host group exists, so a manager group can be seeded.
    foreach ($row in $rows) {
        if (-not $created.ContainsKey($row.Name)) { continue }
        $managers = @{
            user  = @(& $split $row.ManagerUsers)
            group = @(& $split $row.ManagerGroups | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Marker $marker -Connection $connection })
        }
        if (($managers.user.Count + $managers.group.Count) -eq 0) { continue }
        $name = $created[$row.Name]
        if (-not $PSCmdlet.ShouldProcess($name, "Add $($managers.user.Count + $managers.group.Count) member manager(s)")) { continue }
        $added = Add-FreeIPAMember -Method 'hostgroup_add_member_manager' -Name $name -Members $managers -Connection $connection
        $result.ManagersApplied += $added.Completed
        foreach ($problem in $added.Errors) {
            $result.Errors += "Host group '$name': $problem"
            Write-Error "Host group '$name': $problem"
        }
    }

    $result.Hostgroups = $hostgroups.ToArray()

    Write-Verbose ("Host groups: $($result.CreatedHostgroups) created, $($result.UpdatedHostgroups) updated, " +
        "$($result.NestingsApplied) nestings, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
