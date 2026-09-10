function New-EntraEnvironment {
    <#
    .SYNOPSIS
        Seeds the complete test environment, in the only order that works

    .DESCRIPTION
        Runs the fourteen seeding steps in dependency order. Each one also runs standalone, and
        the order here is not a preference - every step depends on the one before it:

        1. Administrative units - the containers everything else is placed in, so they have to
           exist before there is anything to place. Skipping this step is possible and costs
           containment: the objects are still created and still carry the name prefix, but
           teardown then has only the weaker route to find them by.
        2. Users - everything else references them
        3. Groups - membership needs the users to exist, and nesting needs earlier groups
        4. Guest users - the external identities, which join groups rather than being listed
           by them, so they follow the groups instead of travelling with the other users
        5. Licences - assigned to a group and to users, so both must exist first
        6. Devices - registered owners are users
        7. Applications - assignments name both users and groups
        8. Custom directory roles - definitions only, assigned to nobody
        9. Role eligibilities - eligible schedules over those definitions, naming seeded
           principals and scoped to seeded units. Needs Entra ID P2; warns and continues without
        10. Named locations - referenced by the policies below
        11. Conditional Access policies - scoped to groups, conditioned on locations

        At AD parity this creates roughly eleven hundred objects. Everything that can be sent
        through Graph's $batch endpoint is, in chunks of twenty, which is the difference
        between a run of a few minutes and a run of well over an hour.

        A failing step does not stop the run. Steps are isolated because the common failure
        is a permission the app does not hold for one object type, and abandoning the whole
        environment over it would leave a half-seeded tenant that is harder to clean up than
        a complete one. What failed is reported, and the summary says which steps produced
        nothing.

        Re-running over an existing environment is safe but not a no-op. Objects whose names
        already exist will fail to create and be reported; memberships that already exist are
        recognised and skipped quietly. To rebuild cleanly, tear down first with
        -PurgeRecycleBin, because a soft-deleted group keeps its name reserved for thirty
        days and the re-seed will collide with it.

    .PARAMETER Skip
        Steps to leave out. Takes the same names as Remove-EntraEnvironment's -Keep.

    .PARAMETER SkuPartNumber
        Which SKU the licensing step should assign. Defaults to an automatically chosen one
        with free units.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns a summary of everything created

    .OUTPUTS
        EntraEnvironmentResult when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraEnvironment -WhatIf

        DESCRIPTION: Lists every object that would be created, and creates nothing
        OUTPUT: One What if line per object
        USE CASE: Always worth running first against a tenant that is in real use

    .EXAMPLE
        PS> New-EntraEnvironment -ShowProgress -PassThru

        DESCRIPTION: Seeds the full environment with a progress bar
        OUTPUT: The summary, including per-step counts and any failures
        USE CASE: The normal path

    .EXAMPLE
        PS> New-EntraEnvironment -Skip ConditionalAccessPolicies, NamedLocations

        DESCRIPTION: Seeds the directory and access layers but no policy objects
        OUTPUT: None
        USE CASE: A tenant where the app holds no Conditional Access write permission

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraEnvironmentResult')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'The orchestrator creates nothing itself. Every object is created by a step function that calls ShouldProcess for it, and -WhatIf propagates to them through the common parameters, so calling ShouldProcess again here would only add a second prompt per object.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SkuPartNumber',
        Justification = 'Used inside the Licenses step scriptblock, which the analyzer does not follow.')]
    param(
        [Parameter()]
        [ValidateSet('AdministrativeUnits', 'Users', 'GuestUsers', 'Groups', 'Licenses', 'Devices', 'Applications',
            'NamedLocations', 'ConditionalAccessPolicies', 'DirectoryExtensions', 'DirectoryRoles',
            'RoleEligibilities', 'AuthenticationStrengths', 'Containment')]
        [string[]]$Skip,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SkuPartNumber,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    Write-Verbose ("Seeding into tenant '$($connection.TenantName)' ($($connection.TenantId)) " +
        "under prefix '$($marker.Prefix)' on '$($marker.UpnSuffix)'")

    # Named rather than positional so that reordering them is a deliberate edit rather than a
    # diff that looks like a reformat.
    $steps = @(
        [PSCustomObject]@{ Name = 'AdministrativeUnits'; Action = { New-EntraAdministrativeUnit -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'Users'; Action = { New-EntraUser -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'Groups'; Action = { New-EntraGroup -PassThru:$true -ShowProgress:$ShowProgress } }
        # After the groups, because three of the four external identities are placed in one and
        # the group has to exist to be joined. This is the only step that runs out of the order
        # its object type would suggest: guests are users, but they join groups rather than
        # being listed by them, so they cannot go with the rest of the users.
        [PSCustomObject]@{ Name = 'GuestUsers'; Action = { New-EntraGuestUser -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'Licenses'; Action = {
                if ($SkuPartNumber) { Set-EntraLicense -SkuPartNumber $SkuPartNumber -PassThru:$true -ShowProgress:$ShowProgress }
                else { Set-EntraLicense -PassThru:$true -ShowProgress:$ShowProgress }
            }
        }
        [PSCustomObject]@{ Name = 'Devices'; Action = { New-EntraDevice -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'Applications'; Action = { New-EntraApplication -PassThru:$true -ShowProgress:$ShowProgress } }
        # After the applications, because the extension attributes are owned by an application
        # this step creates, and it places that application in the same unit as the others.
        [PSCustomObject]@{ Name = 'DirectoryExtensions'; Action = { New-EntraDirectoryExtension -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'DirectoryRoles'; Action = { New-EntraDirectoryRole -PassThru:$true -ShowProgress:$ShowProgress } }
        # After the roles it makes principals eligible for, and after the groups and units it
        # names as principal and scope. Eligible only, never active - see the function's help.
        # This is the one step that needs Entra ID P2; without it the step warns and the rest of
        # the environment is unaffected.
        [PSCustomObject]@{ Name = 'RoleEligibilities'; Action = { New-EntraRoleEligibility -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'NamedLocations'; Action = { New-EntraNamedLocation -PassThru:$true -ShowProgress:$ShowProgress } }
        # Before the policies, which reference a strength by name and fall back to a built-in
        # if the custom one does not exist yet.
        [PSCustomObject]@{ Name = 'AuthenticationStrengths'; Action = { New-EntraAuthenticationStrength -PassThru:$true -ShowProgress:$ShowProgress } }
        [PSCustomObject]@{ Name = 'ConditionalAccessPolicies'; Action = { New-EntraConditionalAccessPolicy -PassThru:$true -ShowProgress:$ShowProgress } }
        # Last, and not optional in practice. Placement happens seconds after each object is
        # created, so it loses races with replication and a batch that exhausts its retries
        # leaves objects that exist, work, and are simply not in their container. Nothing looks
        # broken until teardown falls back to matching on names. This pass reconciles the
        # difference once the directory has settled.
        [PSCustomObject]@{ Name = 'Containment'; Action = { Update-EntraContainment -PassThru:$true -ShowProgress:$ShowProgress } }
    )

    $outcomes = [System.Collections.Generic.List[object]]::new()
    $stepIndex = 0

    foreach ($step in $steps) {
        $stepIndex++

        if ($Skip -contains $step.Name) {
            Write-Verbose "Skipping step $($step.Name)"
            $outcomes.Add([PSCustomObject]@{
                    PSTypeName = 'EntraEnvironmentStep'
                    Step       = $step.Name
                    Status     = 'Skipped'
                    Count      = 0
                    Items      = @()
                    Error      = $null
                })
            continue
        }

        Write-TestProgress -Activity 'Seeding Entra test environment' -Status $step.Name `
            -PercentComplete ([int](100 * ($stepIndex - 1) / $steps.Count)) -ShowProgress:$ShowProgress

        try {
            $items = @(& $step.Action)
            $outcomes.Add([PSCustomObject]@{
                    PSTypeName = 'EntraEnvironmentStep'
                    Step       = $step.Name
                    Status     = 'Completed'
                    Count      = $items.Count
                    Items      = $items
                    Error      = $null
                })
            Write-Verbose "Step $($step.Name) produced $($items.Count) object(s)"
        }
        catch {
            # Isolated on purpose. See the description: abandoning the run leaves a
            # half-seeded tenant, which is harder to clean up than a complete one.
            Write-Warning "Step '$($step.Name)' failed: $($_.Exception.Message)"
            $outcomes.Add([PSCustomObject]@{
                    PSTypeName = 'EntraEnvironmentStep'
                    Step       = $step.Name
                    Status     = 'Failed'
                    Count      = 0
                    Items      = @()
                    Error      = $_.Exception.Message
                })
        }
    }

    Write-TestProgress -Activity 'Seeding Entra test environment' -Completed -ShowProgress:$ShowProgress

    $failed = @($outcomes | Where-Object { $_.Status -eq 'Failed' })
    if ($failed) {
        Write-Warning ("$($failed.Count) step(s) failed: $(($failed.Step) -join ', '). The rest of the " +
            "environment was still seeded.")
    }

    $result = [PSCustomObject]@{
        PSTypeName = 'EntraEnvironmentResult'
        TenantId   = $connection.TenantId
        TenantName = $connection.TenantName
        Prefix     = $marker.Prefix
        UpnSuffix  = $marker.UpnSuffix
        Steps      = $outcomes.ToArray()
        TotalCount = ($outcomes | Measure-Object -Property Count -Sum).Sum
    }

    if (-not $WhatIfPreference) {
        Write-Verbose ("Seeding complete: $($result.TotalCount) object(s) across " +
            "$(@($outcomes | Where-Object Status -eq 'Completed').Count) step(s)")
    }

    if ($PassThru) { return $result }
}
