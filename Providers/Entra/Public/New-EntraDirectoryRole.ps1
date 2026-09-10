function New-EntraDirectoryRole {
    <#
    .SYNOPSIS
        Creates custom directory role definitions

    .DESCRIPTION
        Custom directory roles are Entra's answer to least privilege, and the closest thing it
        has to Okta's custom admin roles. Three are created, spanning the shapes that matter:
        a read-only role, a narrow write role, and one that spans two resource types.

        **Definitions only. Nothing is assigned to anybody.** That is a deliberate limit rather
        than an oversight. A role definition is inert - it grants nothing until it is assigned
        to a principal at a scope - so creating one is safe in a tenant that is in real use,
        while assigning one is a privilege grant that should be a human decision made once,
        with the assignment visible in the portal, rather than something a seeding script does
        because it can.

        The seeded environment does include a role-assignable group, so if you want to exercise
        an assignment path you have somewhere sensible to point it, deliberately.

        Two things about custom roles are worth knowing. `isEnabled` set to false makes a
        definition that exists and cannot be assigned, which is a state reports routinely miss.
        And `version` is a free string Entra does not interpret, so anything treating it as a
        number is guessing.

    .PARAMETER RoleKey
        Creates only the named roles, by their Key column. Defaults to all of them.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created role definitions

    .OUTPUTS
        EntraDirectoryRole[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraDirectoryRole

        DESCRIPTION: Creates the three custom role definitions, and assigns none of them
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
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
