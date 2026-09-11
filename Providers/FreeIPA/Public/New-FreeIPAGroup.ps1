function New-FreeIPAGroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded FreeIPA groups, nested as Data\FreeIPAGroups.csv describes
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$GroupName,

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

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAGroups.csv'
    $allRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $rows = $allRows

    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($GroupName) {
        $rows = @($allRows | Where-Object { $GroupName -contains $_.Name })
        $unknown = @($GroupName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    # Depth from the full CSV, not the selection, so a partial rebuild still creates a parent
    # before its child when both are selected. A group can name more than one parent, so the
    # depth is the longest path up, and the walk is bounded in case the CSV ever holds a cycle.
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
        TotalGroups     = $rows.Count
        CreatedGroups   = 0
        UpdatedGroups   = 0
        NestingsApplied = 0
        Groups          = @()
        Errors          = @()
    }

    $existing = @{}
    foreach ($group in (Get-FreeIPASeededObject -Type Groups -Connection $connection)) {
        $existing[[string](@($group.cn)[0])] = $group
    }

    $groups = [System.Collections.Generic.List[object]]::new()
    $created = @{}
    $index = 0

    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        $index++
        Write-TestProgress -Activity 'Seeding groups' -Status "$index of $($rows.Count): $name" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA group')) { continue }

        try {
            $description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'group_mod' -Arguments $name -Connection $connection `
                    -Options @{ description = $description } -IgnoreError 'EmptyModlist'
                $result.UpdatedGroups++
                Write-Verbose "Updated group $name"
            }
            else {
                $options = @{ description = $description }
                switch ($row.Type) {
                    'nonposix' { $options['nonposix'] = $true }
                    'external' { $options['external'] = $true }
                    default { if ($row.GidNumber -match '^\d+$') { $options['gidnumber'] = [int]$row.GidNumber } }
                }
                $null = Invoke-FreeIPARequest -Method 'group_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedGroups++
                Write-Verbose "Created group $name"
            }

            $created[$row.Name] = $name
            $groups.Add([PSCustomObject]@{
                    Key      = $row.Name
                    Name     = $name
                    Type     = $row.Type
                    Parents  = @($parentsOf[$row.Name])
                    Category = $row.Category
                })
        }
        catch {
            $message = "Failed to create group '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-TestProgress -Activity 'Seeding groups' -Completed -ShowProgress:$ShowProgress

    # Nesting, one call per parent, naming every child that exists. A parent outside the
    # selection is fine if it already exists in the realm; one that does not is skipped.
    $childrenOf = @{}
    foreach ($row in $rows) {
        if (-not $created.ContainsKey($row.Name)) { continue }
        foreach ($parentKey in $parentsOf[$row.Name]) {
            $parentName = Resolve-FreeIPASeedName -Key $parentKey -Marker $marker -Connection $connection
            if (-not ($created.ContainsKey($parentKey) -or $existing.ContainsKey($parentName))) {
                Write-Warning "Group '$($created[$row.Name])' names parent '$parentKey', which does not exist. Left unnested."
                continue
            }
            if (-not $childrenOf.ContainsKey($parentName)) { $childrenOf[$parentName] = [System.Collections.Generic.List[string]]::new() }
            $childrenOf[$parentName].Add($created[$row.Name])
        }
    }

    foreach ($parentName in ($childrenOf.Keys | Sort-Object)) {
        if (-not $PSCmdlet.ShouldProcess($parentName, "Nest $($childrenOf[$parentName].Count) member group(s)")) { continue }
        try {
            $outcome = Invoke-FreeIPARequest -Method 'group_add_member' -Arguments $parentName -Connection $connection `
                -Options @{ group = [object[]]@($childrenOf[$parentName]) }
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

    $result.Groups = $groups.ToArray()

    Write-Verbose ("Groups: $($result.CreatedGroups) created, $($result.UpdatedGroups) updated, " +
        "$($result.NestingsApplied) nestings, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
