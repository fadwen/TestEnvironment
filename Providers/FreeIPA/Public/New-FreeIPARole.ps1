function New-FreeIPARole {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded permissions, privileges and roles from Data\FreeIPAPermissions.csv, Data\FreeIPAPrivileges.csv and Data\FreeIPARoles.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RoleName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $dataPath = Get-FreeIPADataPath

    $permissionRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPAPermissions.csv') -Encoding UTF8)
    $privilegeRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPAPrivileges.csv') -Encoding UTF8)
    $rolePath = Join-Path -Path $dataPath -ChildPath 'FreeIPARoles.csv'
    $roleRows = @(Import-Csv -Path $rolePath -Encoding UTF8)
    if ($RoleName) {
        $roleRows = @($roleRows | Where-Object { $RoleName -contains $_.Name })
        $unknown = @($RoleName | Where-Object { $roleRows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $rolePath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRoles         = $roleRows.Count
        CreatedRoles       = 0
        UpdatedRoles       = 0
        PermissionsCreated = 0
        PrivilegesCreated  = 0
        MembershipsApplied = 0
        Roles              = @()
        Errors             = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }
    $describe = { param($text) ('{0} {1}' -f $text, $marker.Marker).Trim() }
    $record = { param($problem) $result.Errors += $problem; Write-Error $problem }

    $existingPermissions = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Permissions -Connection $connection)) { $existingPermissions[[string](@($entry.cn)[0])] = $entry }
    $existingPrivileges = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Privileges -Connection $connection)) { $existingPrivileges[[string](@($entry.cn)[0])] = $entry }
    $existingRoles = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Roles -Connection $connection)) { $existingRoles[[string](@($entry.cn)[0])] = $entry }

    # --- Permissions ----------------------------------------------------------------------------
    foreach ($row in $permissionRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA permission')) { continue }
        try {
            $options = @{
                ipapermright = [object[]]@(& $split $row.Rights)
                type         = $row.Type
            }
            if ($row.Attributes) { $options['attrs'] = [object[]]@(& $split $row.Attributes) }
            if ($row.Filter) { $options['extratargetfilter'] = [object[]]@($row.Filter.Replace('{tag}', $marker.Tag).Replace('{prefix}', $marker.NamePrefix)) }

            if ($existingPermissions.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'permission_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'permission_add' -Arguments $name -Options $options -Connection $connection
                $result.PermissionsCreated++
            }
        }
        catch { & $record "Failed to create permission '$name': $($_.Exception.Message)" }
    }

    # --- Privileges -----------------------------------------------------------------------------
    foreach ($row in $privilegeRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA privilege')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($existingPrivileges.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'privilege_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'privilege_add' -Arguments $name -Options $options -Connection $connection
                $result.PrivilegesCreated++
            }
            $outcome = Add-FreeIPAMember -Method 'privilege_add_permission' -Name $name -Members @{ permission = @(& $resolve $row.Permissions 'Name') } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }
        }
        catch { & $record "Failed to create privilege '$name': $($_.Exception.Message)" }
    }

    # --- Roles ----------------------------------------------------------------------------------
    $roles = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $roleRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA role')) { continue }
        try {
            $options = @{ description = & $describe $row.Description }
            if ($existingRoles.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'role_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedRoles++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'role_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedRoles++
                Write-Verbose "Created role $name"
            }

            $outcome = Add-FreeIPAMember -Method 'role_add_privilege' -Name $name -Members @{ privilege = @(& $resolve $row.Privileges 'Name') } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }

            $outcome = Add-FreeIPAMember -Method 'role_add_member' -Name $name -Connection $connection -Members @{
                user  = @(& $split $row.Users)
                group = @(& $resolve $row.Groups 'Name')
                host  = @(& $resolve $row.Hosts 'Host')
            }
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }

            $roles.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Privileges = @(& $split $row.Privileges) })
        }
        catch { & $record "Failed to create role '$name': $($_.Exception.Message)" }
    }

    $result.Roles = $roles.ToArray()
    Write-Verbose "RBAC: $($result.PermissionsCreated) permissions, $($result.PrivilegesCreated) privileges, $($result.CreatedRoles) roles created, $($result.UpdatedRoles) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
