function New-AuthentikRole {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Authentik RBAC roles from Data\AuthentikRoles.csv and assigns them to groups
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RoleName,

        [Parameter()]
        [switch]$SkipGroups,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikRoles.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($RoleName) {
        $rows = @($rows | Where-Object { $RoleName -contains $_.Name })
        $unknown = @($RoleName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRoles          = $rows.Count
        CreatedRoles        = 0
        UpdatedRoles        = 0
        PermissionsAssigned = 0
        GroupsAssigned      = 0
        Roles               = @()
        Errors              = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Roles -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    $groupByKey = @{}
    if (-not $SkipGroups) {
        foreach ($group in (Get-AuthentikSeededObject -Type Groups -Connection $connection)) {
            if ($group.attributes.PSObject.Properties['labKey']) { $groupByKey[[string]$group.attributes.labKey] = $group }
        }
    }

    $roles = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.DisplayName

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik role')) { continue }

        try {
            $role = $null
            if ($existingByName.ContainsKey($name)) {
                $role = $existingByName[$name]
                $result.UpdatedRoles++
                Write-Verbose "Role $name already exists"
            }
            else {
                $role = Invoke-AuthentikRequest -Method POST -Path '/rbac/roles/' -Body @{ name = $name } -Connection $connection
                $result.CreatedRoles++
                Write-Verbose "Created role $name"
            }

            # Global permissions, by codename. Assigning one already held is not an error.
            $permissions = @($row.Permissions -split ';' | Where-Object { $_ })
            if ($permissions.Count -gt 0) {
                $null = Invoke-AuthentikRequest -Method POST -Path "/rbac/permissions/assigned_by_roles/$($role.pk)/assign/" `
                    -Body @{ permissions = $permissions } -Connection $connection
                $result.PermissionsAssigned += $permissions.Count
            }

            $assigned = @()
            if (-not $SkipGroups) {
                foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) {
                    if (-not $groupByKey.ContainsKey($key)) {
                        $message = "Role '$name' names group '$key', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }
                    $group = $groupByKey[$key]
                    $current = @($group.roles | ForEach-Object { [string]$_ })
                    if ($current -notcontains [string]$role.pk) {
                        $null = Invoke-AuthentikRequest -Method PATCH -Path "/core/groups/$($group.pk)/" `
                            -Body @{ roles = @($current + [string]$role.pk) } -Connection $connection
                        $group.roles = @($current + [string]$role.pk)
                    }
                    $assigned += $key
                    $result.GroupsAssigned++
                }
            }

            $roles.Add([PSCustomObject]@{
                    Id          = [string]$role.pk
                    Key         = $row.Name
                    Name        = $name
                    Permissions = $permissions
                    Groups      = $assigned
                })
        }
        catch {
            $message = "Failed to create role '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Roles = $roles.ToArray()

    Write-Verbose ("Roles: $($result.CreatedRoles) created, $($result.UpdatedRoles) existing, " +
        "$($result.PermissionsAssigned) permissions, $($result.GroupsAssigned) group assignments, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
