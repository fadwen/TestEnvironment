function New-PingOneGroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded groups, nests them, and gives the dynamic ones their filters
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection
    $marker = Get-PingOneSeedMarker -Prefix $connection.Prefix

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneGroups.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $populationNameByKey = @{}
    foreach ($populationRow in (Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOnePopulations.csv') -Encoding UTF8)) {
        $populationNameByKey[$populationRow.Key] = Resolve-PingOneSeedName -Key $populationRow.Name `
            -Kind DisplayName -Connection $connection
    }
    $populationId = @{}
    foreach ($population in (Invoke-PingOneRequest -Method GET -Path 'populations' -Paginate -Connection $connection)) {
        $populationId[[string]$population.name] = $population.id
    }

    $groupByName = @{}
    foreach ($group in (Invoke-PingOneRequest -Method GET -Path 'groups' -Paginate -Connection $connection)) {
        $groupByName[[string]$group.name] = $group
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $idByKey = @{}

    foreach ($row in $rows) {
        $name = Resolve-PingOneSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        if ($groupByName.ContainsKey($name)) {
            Write-Verbose "Group $name already exists; reusing"
            $idByKey[$row.Key] = $groupByName[$name].id
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $groupByName[$name].id })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create PingOne group')) { continue }

        $body = @{
            name        = $name
            description = '{0} {1}' -f $row.Description, $marker.Tag
        }

        # A group scoped to a population.
        $scopedPopulationId = $null
        if ($row.Population) {
            $scopedName = $populationNameByKey[$row.Population]
            if ($scopedName -and $populationId.ContainsKey($scopedName)) {
                $scopedPopulationId = $populationId[$scopedName]
            }
            else {
                $errors.Add("Population '$($row.Population)' for group $name does not exist; run New-PingOnePopulation first")
                continue
            }
        }

        # The filter column names a shape rather than holding raw SCIM, because the population
        # ids it has to reference do not exist until the seed runs.
        switch ($row.UserFilter) {
            'population' {
                $body['userFilter'] = 'population.id eq "{0}"' -f $scopedPopulationId
            }
            'nobody' {
                # Valid, and matches no one. The username can never exist, because PingOne
                # refuses a username containing a space.
                $body['userFilter'] = 'username eq "{0}nobody matches this"' -f $marker.Prefix
            }
            default {
                if ($scopedPopulationId) { $body['population'] = @{ id = $scopedPopulationId } }
            }
        }

        try {
            $result = Invoke-PingOneRequest -Method POST -Path 'groups' -Body $body -Connection $connection
            $idByKey[$row.Key] = $result.id
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id; Filter = $body['userFilter'] })
            Write-Verbose "Created group $name"
        }
        catch {
            $errors.Add("Could not create group ${name}: $($_.Exception.Message)")
            Write-Warning "Could not create group ${name}: $($_.Exception.Message)"
        }
    }

    # Nesting, once every group in the step exists, so the order of rows cannot matter.
    $nestingsApplied = 0
    foreach ($row in $rows) {
        if (-not $row.Parent) { continue }

        $childId = $idByKey[$row.Key]
        $parentId = $idByKey[$row.Parent]
        if (-not $parentId) {
            $parentRow = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneGroups.csv') -Encoding UTF8 |
                    Where-Object Key -eq $row.Parent)
            if ($parentRow) {
                $parentName = Resolve-PingOneSeedName -Key $parentRow[0].Name -Kind DisplayName -Connection $connection
                if ($groupByName.ContainsKey($parentName)) { $parentId = $groupByName[$parentName].id }
            }
        }

        if (-not $childId -or -not $parentId) {
            $errors.Add("Could not nest '$($row.Key)' in '$($row.Parent)': one of them does not exist")
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$($row.Key) -> $($row.Parent)", 'Nest PingOne group')) { continue }

        try {
            $null = Invoke-PingOneRequest -Method POST -Path "groups/$childId/memberOfGroups" `
                -Body @{ id = $parentId } -Connection $connection -IgnoreError 'UNIQUENESS_VIOLATION'
            $nestingsApplied++
        }
        catch {
            $errors.Add("Could not nest '$($row.Key)' in '$($row.Parent)': $($_.Exception.Message)")
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalGroups     = @($rows).Count
            CreatedGroups   = $created.Count
            ReusedGroups    = $reused.Count
            NestingsApplied = $nestingsApplied
            Groups          = (@($created) + @($reused))
            Errors          = $errors.ToArray()
        }
    }
}
