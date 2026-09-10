function New-AuthentikGroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Authentik groups, nested as Data\AuthentikGroups.csv describes
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

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikGroups.csv'
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
        TotalGroups   = $rows.Count
        CreatedGroups = 0
        UpdatedGroups = 0
        Groups        = @()
        Errors        = @()
    }

    # Groups that already exist, keyed by CSV key, so a parent created in an earlier run or
    # earlier in this loop resolves to its pk.
    $pkByKey = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Groups -Connection $connection)) {
        if ($existing.attributes.PSObject.Properties['labKey']) { $pkByKey[[string]$existing.attributes.labKey] = [string]$existing.pk }
    }

    $groups = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.DisplayName
        $index++
        Write-TestProgress -Activity 'Seeding groups' -Status "$index of $($rows.Count): $name" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik group')) { continue }

        try {
            $parents = @()
            foreach ($parentKey in $parentsOf[$row.Name]) {
                if ($pkByKey.ContainsKey($parentKey)) { $parents += $pkByKey[$parentKey] }
                else { Write-Warning "Group '$name' names parent '$parentKey', which does not exist yet. Created without it." }
            }

            $attributes = [ordered]@{}
            $attributes[$marker.Attribute] = $marker.Tag
            $attributes['labKey'] = $row.Name
            $attributes['labCategory'] = $row.Category
            $attributes['labDescription'] = $row.Description

            $body = @{
                name         = $name
                is_superuser = $false
                parents      = $parents
                attributes   = $attributes
            }

            $group = $null
            if ($pkByKey.ContainsKey($row.Name)) {
                $group = Invoke-AuthentikRequest -Method PATCH -Path "/core/groups/$($pkByKey[$row.Name])/" -Body $body -Connection $connection
                $result.UpdatedGroups++
                Write-Verbose "Updated group $name"
            }
            else {
                $group = Invoke-AuthentikRequest -Method POST -Path '/core/groups/' -Body $body -Connection $connection
                $result.CreatedGroups++
                Write-Verbose "Created group $name"
            }

            $pkByKey[$row.Name] = [string]$group.pk

            $groups.Add([PSCustomObject]@{
                    Id       = [string]$group.pk
                    Key      = $row.Name
                    Name     = $name
                    Parent   = $row.Parent
                    Category = $row.Category
                })
        }
        catch {
            $message = "Failed to create group '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Groups = $groups.ToArray()
    Write-TestProgress -Activity 'Seeding groups' -Completed -ShowProgress:$ShowProgress

    Write-Verbose ("Groups: $($result.CreatedGroups) created, $($result.UpdatedGroups) updated, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
