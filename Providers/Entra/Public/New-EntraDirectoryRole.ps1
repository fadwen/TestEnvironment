function New-EntraDirectoryRole {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates custom directory role definitions
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraDirectoryRole')]
    param(
        [Parameter()]
        [string[]]$RoleKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraDirectoryRoles')
    if ($RoleKey) {
        $definitions = @($definitions | Where-Object { $RoleKey -contains $_.Key })
        $missing = @($RoleKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for role key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    $existing = @(Get-EntraSeededObject -Type DirectoryRoles -Connection $connection)
    $created = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName

        Write-TestProgress -Activity 'Seeding custom directory roles' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        $already = $existing | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1
        if ($already) {
            Write-Verbose "Custom role '$displayName' already exists"
            $created.Add([PSCustomObject]@{
                    PSTypeName  = 'EntraDirectoryRole'
                    Key         = $definition.Key
                    Id          = $already.id
                    DisplayName = $displayName
                    Actions     = @($already.rolePermissions.allowedResourceActions)
                    Purpose     = $definition.Purpose
                })
            continue
        }

        $actions = @($definition.ResourceActions -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        if ($actions.Count -eq 0) {
            Write-Error "Custom role '$($definition.Key)' lists no resource actions." -ErrorAction Continue
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create custom directory role definition')) { continue }

        try {
            $role = Invoke-EntraRequest -Method POST -Connection $connection `
                -Path '/roleManagement/directory/roleDefinitions' -Body @{
                displayName     = $displayName
                description     = $marker.Description
                isEnabled       = $true
                rolePermissions = @(@{ allowedResourceActions = $actions })
            }
        }
        catch {
            Write-Error "Failed to create custom role '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName  = 'EntraDirectoryRole'
                Key         = $definition.Key
                Id          = $role.id
                DisplayName = $displayName
                Actions     = $actions
                Purpose     = $definition.Purpose
            })

        Write-Verbose "Created custom role '$displayName' ($($role.id))"
    }

    Write-TestProgress -Activity 'Seeding custom directory roles' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
