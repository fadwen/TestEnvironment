function Update-EntraContainment {
    <#
    .SYNOPSIS
        Places any seeded object that is not in its administrative unit

    .DESCRIPTION
        Reconciles what the containers hold against what the tenant actually contains, and
        fixes the difference.

        This exists because placement is the one part of seeding that can fail without
        anything else being wrong. The references are added seconds after the objects are
        created, so they lose races with replication, and a batch that exhausts its retries
        leaves objects that exist, work, and are simply not in their container. Nothing looks
        broken until teardown falls back to matching on names.

        Running it is cheap and idempotent: objects already in their unit are recognised and
        skipped, so it is safe to run repeatedly and safe to run against an environment that
        is already correct.

        It reconciles in one direction only. An object in a unit that this module cannot
        otherwise account for is reported and left alone, never removed - the unit is a
        container this module created, but membership of it is not proof that this module
        should be managing what somebody else put in it.

    .PARAMETER ObjectType
        Which classes to reconcile. Defaults to all four that can belong to a unit.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns a per-type summary

    .OUTPUTS
        EntraContainmentResult[] when -PassThru is supplied

    .EXAMPLE
        PS> Update-EntraContainment

        DESCRIPTION: Places anything that was created but not contained
        OUTPUT: None
        USE CASE: The last step of New-EntraEnvironment, and after any partial seed

    .EXAMPLE
        PS> Update-EntraContainment -PassThru | Format-Table

        DESCRIPTION: Reports how many of each type were already contained and how many were added
        OUTPUT: One row per object type
        USE CASE: Confirming teardown will be able to use the strong ownership route

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraContainmentResult')]
    param(
        [Parameter()]
        [ValidateSet('Users', 'Groups', 'Devices', 'Applications')]
        [string[]]$ObjectType = @('Users', 'Groups', 'Devices', 'Applications'),

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    # The Graph type name behind each class, needed for the typed member query.
    $graphType = @{
        Users        = 'user'
        Groups       = 'group'
        Devices      = 'device'
        Applications = 'application'
    }

    $units = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection)
    $results = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($type in $ObjectType) {
        $index++
        Write-TestProgress -Activity 'Reconciling containment' -Status $type `
            -PercentComplete ([int](100 * $index / $ObjectType.Count)) -ShowProgress:$ShowProgress

        $unitName = '{0}{1}' -f $marker.Prefix, $type
        $unit = $units | Where-Object { $_.displayName -eq $unitName } | Select-Object -First 1
        if (-not $unit) {
            Write-Warning "No administrative unit called '$unitName' exists, so $type cannot be contained."
            continue
        }

        # Everything the module can account for, by either route.
        $seeded = @(Get-EntraSeededObject -Type $type -Connection $connection)
        if ($seeded.Count -eq 0) { continue }

        $contained = @{}
        try {
            foreach ($member in (Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                        -Path "/directory/administrativeUnits/$($unit.id)/members/microsoft.graph.$($graphType[$type])" `
                        -Query @{ '$select' = 'id' })) {
                $contained[$member.id] = $true
            }
        }
        catch {
            Write-Warning "Could not read the members of '$unitName': $($_.Exception.Message)"
            continue
        }

        $missing = @($seeded | Where-Object { -not $contained.ContainsKey($_.id) })

        $added = 0
        if ($missing.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess($unitName, "Place $($missing.Count) $type")) {
                $added = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($missing.id) -Connection $connection `
                    -Activity "Placing $type in $unitName" -ShowProgress:$ShowProgress
            }
        }

        Write-Verbose "$type : $($seeded.Count) seeded, $($contained.Count) already contained, $($missing.Count) missing, $added placed"

        $results.Add([PSCustomObject]@{
                PSTypeName        = 'EntraContainmentResult'
                ObjectType        = $type
                AdministrativeUnit = $unitName
                Seeded            = $seeded.Count
                AlreadyContained  = $contained.Count
                Missing           = $missing.Count
                Placed            = $added
            })
    }

    Write-TestProgress -Activity 'Reconciling containment' -Completed -ShowProgress:$ShowProgress

    $stillMissing = @($results | Where-Object { $_.Missing -gt $_.Placed })
    if ($stillMissing.Count -gt 0) {
        Write-Warning ("Some objects could not be placed in their administrative unit. They remain identifiable " +
            "by the name prefix, so teardown will still find them, but by the weaker route. Run this again once " +
            "the directory has settled.")
    }

    if ($PassThru) { return $results.ToArray() }
}
