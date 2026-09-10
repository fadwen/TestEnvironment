function New-EntraAdministrativeUnit {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the administrative units that contain the seeded environment
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraAdministrativeUnit')]
    param(
        [Parameter()]
        [ValidateSet('Users', 'Groups', 'Devices', 'Applications')]
        [string[]]$UnitKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(
        [PSCustomObject]@{ Key = 'Users'; Suffix = 'Users'; Description = 'Seeded user accounts' }
        [PSCustomObject]@{ Key = 'Groups'; Suffix = 'Groups'; Description = 'Seeded groups' }
        [PSCustomObject]@{ Key = 'Devices'; Suffix = 'Devices'; Description = 'Seeded device objects' }
        [PSCustomObject]@{ Key = 'Applications'; Suffix = 'Applications'; Description = 'Seeded application registrations' }
    )

    if ($UnitKey) {
        $definitions = @($definitions | Where-Object { $UnitKey -contains $_.Key })
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $existing = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection)
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.Suffix

        Write-TestProgress -Activity 'Seeding administrative units' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        # Re-running over an existing environment must not create a second container with the
        # same name, because teardown would then find members split across both.
        $already = $existing | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1
        if ($already) {
            Write-Verbose "Administrative unit '$displayName' already exists ($($already.id))"
            $created.Add([PSCustomObject]@{
                    PSTypeName  = 'EntraAdministrativeUnit'
                    Key         = $definition.Key
                    Id          = $already.id
                    DisplayName = $displayName
                    Created     = $false
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create administrative unit')) { continue }

        try {
            $unit = Invoke-EntraRequest -Method POST -Path '/directory/administrativeUnits' -Body @{
                displayName = $displayName
                # The seed tag goes in the description, as it does for groups, so a unit is
                # identifiable even if somebody renames it.
                description = "$($definition.Description). $($marker.Description)"
                visibility  = 'Public'
            }
        }
        catch {
            Write-Error "Failed to create administrative unit '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName  = 'EntraAdministrativeUnit'
                Key         = $definition.Key
                Id          = $unit.id
                DisplayName = $displayName
                Created     = $true
            })

        Write-Verbose "Created administrative unit '$displayName' ($($unit.id))"
    }

    Write-TestProgress -Activity 'Seeding administrative units' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
