function Remove-EntraEnvironment {
    <#
    .SYNOPSIS
        Removes everything this module created, and refuses to remove anything else

    .DESCRIPTION
        Tears the seeded environment down in the reverse of the order it was built, deleting
        only objects whose ownership has been proven by Get-EntraSeededObject.

        Ownership is proven, never assumed. An object that merely looks like test data is
        left alone and reported. That rule exists because this module seeds into a tenant
        that is in real use: a group called "Department Finance" that somebody created by
        hand is one prefix collision away from being deleted by a tool that matched on name
        alone, and a deleted Entra object is recoverable only by somebody who notices inside
        thirty days.

        The order is forced by Entra's own dependencies, and three steps in it are not obvious:

        - Role eligibilities are withdrawn before anything else, because they reference both a
          role definition and a principal and a live one blocks the definition from being
          deleted. They are also withdrawn rather than deleted: a schedule has no DELETE, so the
          removal is a second request posted with action adminRemove.

        - Licences are removed from the seeded group before the group is deleted. Verified
          against a live tenant: DELETE on a group holding an active licence fails with
          "A group with active licenses assigned cannot be deleted". The removal is also
          asynchronous, so the delete is retried rather than attempted once.
        - Conditional Access policies and named locations go first, because a policy holding
          a reference to a location or a group blocks nothing from being deleted but does
          leave a policy pointing at an object that no longer exists, which is a worse state
          to leave a live tenant in than either extreme.

        Deletion is soft. Users, groups and applications go to the directory recycle bin for
        thirty days, and they behave differently there: a deleted user has its UPN rewritten
        to free the original for reuse, while a deleted group keeps its displayName and
        mailNickname reserved. So a tear-down-then-immediately-re-seed collides on groups and
        not on users unless -PurgeRecycleBin is used. Devices, named locations and
        Conditional Access policies are not soft-deleted at all.

        -WhatIf beats -Force. If both are passed, nothing is deleted.

    .PARAMETER Keep
        Layers to leave in place. Takes the same names as New-EntraEnvironment's -Skip.

    .PARAMETER PurgeRecycleBin
        Permanently removes the soft-deleted objects afterwards, so a re-seed does not collide
        with a reserved group name. This is irreversible - purged objects cannot be restored.

    .PARAMETER Force
        Suppresses the confirmation prompt

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns what was removed, and what was left alone

    .OUTPUTS
        EntraTeardownResult when -PassThru is supplied

    .EXAMPLE
        PS> Remove-EntraEnvironment -WhatIf

        DESCRIPTION: Lists exactly what would be deleted, and deletes nothing
        OUTPUT: One What if line per object
        USE CASE: Always worth running first

    .EXAMPLE
        PS> Remove-EntraEnvironment -Force -PurgeRecycleBin

        DESCRIPTION: Removes everything and empties the recycle bin of it
        OUTPUT: None
        USE CASE: Tearing down before an immediate re-seed, where a reserved group name would collide

    .EXAMPLE
        PS> Remove-EntraEnvironment -Keep Users, Groups -Force

        DESCRIPTION: Removes the policy, application and device layers but leaves the directory
        OUTPUT: None
        USE CASE: Rebuilding the access layer over a directory that is expensive to recreate

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('EntraTeardownResult')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Keep',
        Justification = 'Used inside the shouldRun scriptblock, which the analyzer does not follow.')]
    param(
        [Parameter()]
        [ValidateSet('ConditionalAccessPolicies', 'AuthenticationStrengths', 'NamedLocations',
            'RoleEligibilities', 'DirectoryRoles', 'Licenses', 'Applications', 'Devices', 'Groups',
            'Users', 'AdministrativeUnits')]
        [string[]]$Keep,

        [Parameter()]
        [switch]$PurgeRecycleBin,

        [Parameter()]
        [switch]$RemoveServiceApp,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    # -Force must not override -WhatIf. ShouldProcess already handles this, but ConfirmPreference
    # is what suppresses the prompt, and setting it unconditionally would make -Force silently
    # win over a -WhatIf passed alongside it.
    if ($Force -and -not $WhatIfPreference) {
        $ConfirmPreference = 'None'
    }

    $removed = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()

    $shouldRun = { param($Layer) $Keep -notcontains $Layer }

    $record = {
        param($Type, $Name, $Id, $Outcome, $Detail)
        $entry = [PSCustomObject]@{
            PSTypeName = 'EntraTeardownEntry'
            Type       = $Type
            Name       = $Name
            Id         = $Id
            Outcome    = $Outcome
            Detail     = $Detail
        }
        if ($Outcome -eq 'Removed') { $removed.Add($entry) } else { $skipped.Add($entry) }
    }

    # A generic delete used by most layers. Every delete retries a 404, because an object
    # touched moments earlier in this same teardown may not be addressable on every replica.
    # ErrorMatch adds a second retry condition for the layers where a dependency is torn down
    # asynchronously and the delete has to wait for it.
    $deleteObject = {
        param($Path, $Type, $Name, $Id, $ErrorMatch)
        try {
            $deleteArgs = @{
                Method          = 'DELETE'
                Path            = $Path
                RetryOnNotFound = $true
                Connection      = $connection
            }
            if ($ErrorMatch) { $deleteArgs.RetryOnErrorMatch = $ErrorMatch }
            Invoke-EntraRequest @deleteArgs | Out-Null
            & $record $Type $Name $Id 'Removed' $null
            Write-Verbose "Deleted $Type '$Name'"
        }
        catch {
            & $record $Type $Name $Id 'Failed' $_.Exception.Message
            Write-Warning "Could not delete $Type '${Name}': $($_.Exception.Message)"
        }
    }

    # Batched deletion for the high-volume layers. At AD parity teardown removes roughly eleven
    # hundred objects, and one DELETE each would take longer than the seed that created them.
    # The per-object ShouldProcess is still asked first, so -WhatIf and -Confirm behave exactly
    # as they do on the serial path.
    $deleteMany = {
        param($UrlPrefix, $Type, $Objects, $NameProperty)

        $approved = [System.Collections.Generic.List[object]]::new()
        foreach ($object in $Objects) {
            $name = $object.$NameProperty
            if (-not $PSCmdlet.ShouldProcess($name, "Delete $Type")) { continue }
            $approved.Add([PSCustomObject]@{
                    Reference = $object.id
                    Method    = 'DELETE'
                    Url       = "$UrlPrefix/$($object.id)"
                    Name      = $name
                })
        }

        if ($approved.Count -eq 0) { return }

        $results = @(Invoke-EntraBatch -Request $approved.ToArray() -Connection $connection -RetryOnNotFound `
                -Activity "Deleting $Type" -ShowProgress:$ShowProgress)

        $nameById = @{}
        foreach ($item in $approved) { $nameById[$item.Reference] = $item.Name }

        foreach ($result in $results) {
            $name = $nameById[$result.Reference]
            if ($result.Success) {
                & $record $Type $name $result.Reference 'Removed' $null
            }
            else {
                & $record $Type $name $result.Reference 'Failed' $result.Error
                Write-Warning "Could not delete $Type '${name}': $($result.Error)"
            }
        }
    }

    Write-Verbose "Tearing down objects under prefix '$($marker.Prefix)' in tenant $($connection.TenantName)"

    # --- 1. Conditional Access policies -------------------------------------------------
    if (& $shouldRun 'ConditionalAccessPolicies') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Conditional Access policies' -PercentComplete 5 -ShowProgress:$ShowProgress
        foreach ($policy in (Get-EntraSeededObject -Type ConditionalAccessPolicies -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($policy.displayName, 'Delete Conditional Access policy')) { continue }
            & $deleteObject "/identity/conditionalAccess/policies/$($policy.id)" 'ConditionalAccessPolicy' $policy.displayName $policy.id
        }
    }

    # --- 1b. Authentication strengths ----------------------------------------------------
    # After the policies, because a strength still referenced by one cannot be deleted, and
    # for the same reason as the named locations below the reference is dropped asynchronously.
    if (& $shouldRun 'AuthenticationStrengths') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Authentication strengths' -PercentComplete 10 -ShowProgress:$ShowProgress
        foreach ($strength in (Get-EntraSeededObject -Type AuthenticationStrengths -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($strength.displayName, 'Delete authentication strength')) { continue }
            & $deleteObject "/identity/conditionalAccess/authenticationStrength/policies/$($strength.id)" `
                'AuthenticationStrength' $strength.displayName $strength.id 'referenced by|in use'
        }
    }

    # --- 1c. Role eligibilities ----------------------------------------------------------
    # Before the role definitions below, and that ordering is forced: a definition with a live
    # eligibility pointing at it cannot be deleted. Before the users and groups as well, because
    # deleting a principal leaves its eligibility behind pointing at an object that no longer
    # resolves, which is a worse state to leave a live tenant in than either extreme.
    #
    # An eligibility is not deleted, it is withdrawn. There is no DELETE on a schedule - the
    # removal is itself a request, posted with action adminRemove against the same collection
    # that created it, so this cannot use the generic delete helper.
    # Set when the eligibilities could not be enumerated, which forces the role definitions to be
    # kept below. Deleting a definition is what makes an eligibility unfindable forever, so
    # "could not tell" has to be treated differently from "there are none".
    $eligibilityReadFailed = $false

    if (& $shouldRun 'RoleEligibilities') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Role eligibilities' -PercentComplete 11 -ShowProgress:$ShowProgress

        $eligibilities = @()
        try {
            $eligibilities = @(Get-EntraSeededObject -Type RoleEligibilities -Connection $connection -ErrorAction Stop)
        }
        catch {
            $eligibilityReadFailed = $true
            Write-Warning ("Could not enumerate the role eligibilities: $($_.Exception.Message). Keeping the " +
                'custom role definitions, because deleting them would leave any eligibility that does exist ' +
                'pointing at a role that no longer resolves, with nothing left to identify it by.')
        }

        foreach ($eligibility in $eligibilities) {
            if (-not $PSCmdlet.ShouldProcess($eligibility.displayName, 'Remove eligible role schedule')) { continue }

            try {
                Invoke-EntraRequest -Method POST -Connection $connection -RetryOnNotFound `
                    -Path '/roleManagement/directory/roleEligibilityScheduleRequests' -Body @{
                    action           = 'adminRemove'
                    principalId      = $eligibility.principalId
                    roleDefinitionId = $eligibility.roleDefinitionId
                    directoryScopeId = $eligibility.directoryScopeId
                    justification    = $marker.Description
                } | Out-Null
                & $record 'RoleEligibility' $eligibility.displayName $eligibility.id 'Removed' $null
                Write-Verbose "Withdrew eligibility '$($eligibility.displayName)'"
            }
            catch {
                & $record 'RoleEligibility' $eligibility.displayName $eligibility.id 'Failed' $_.Exception.Message
                Write-Warning ("Could not withdraw the eligibility '$($eligibility.displayName)': " +
                    "$($_.Exception.Message). The role definition below will refuse to delete while it stands.")
            }
        }
    }

    # --- 1d. Custom directory roles ------------------------------------------------------
    # Definitions only. This module never makes an active assignment, and the eligible schedules
    # it does create were withdrawn immediately above, so by this point nothing points at them.
    if ((& $shouldRun 'DirectoryRoles') -and -not $eligibilityReadFailed) {
        Write-TestProgress -Activity 'Removing environment' -Status 'Custom directory roles' -PercentComplete 12 -ShowProgress:$ShowProgress
        foreach ($role in (Get-EntraSeededObject -Type DirectoryRoles -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($role.displayName, 'Delete custom directory role')) { continue }

            # Retried on the reference error, for the same reason the named locations below are:
            # withdrawing an eligibility is asynchronous, so the step above can report success
            # and the definition still be refused for a few seconds afterwards. Ordering the
            # steps correctly is necessary but not sufficient.
            & $deleteObject "/roleManagement/directory/roleDefinitions/$($role.id)" 'DirectoryRole' `
                $role.displayName $role.id 'in use|referenced|active assignment|eligible'
        }
    }

    # --- 2. Named locations -------------------------------------------------------------
    if (& $shouldRun 'NamedLocations') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Named locations' -PercentComplete 15 -ShowProgress:$ShowProgress
        foreach ($location in (Get-EntraSeededObject -Type NamedLocations -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($location.displayName, 'Delete named location')) { continue }

            # A trusted location cannot be deleted while it is trusted. Verified against a
            # live tenant: the DELETE fails with error 1177, "cannot be deleted because it is
            # marked as a Trusted location. You have to unmark this named location before
            # deletion." So unmark it first. The same shape as the licensed group below, and
            # like that one it is only discoverable by trying.
            if ($location.isTrusted) {
                try {
                    Invoke-EntraRequest -Method PATCH -Path "/identity/conditionalAccess/namedLocations/$($location.id)" `
                        -RetryOnNotFound -Connection $connection -Body @{
                        '@odata.type' = '#microsoft.graph.ipNamedLocation'
                        isTrusted     = $false
                    } | Out-Null
                    Write-Verbose "Unmarked '$($location.displayName)' as trusted so it can be deleted"
                }
                catch {
                    Write-Warning ("Could not unmark '$($location.displayName)' as trusted: $($_.Exception.Message). " +
                        'The delete below will fail.')
                }
            }

            # Retried on both of the states that block a delete, because Conditional Access
            # clears both asynchronously and ordering the steps correctly is necessary but not
            # sufficient:
            #   1178 - still referenced by a policy, which was deleted in the step above
            #   1177 - still marked trusted, which was cleared by the PATCH immediately above
            # Verified live: the PATCH succeeds, isTrusted reads back False, and the DELETE
            # issued straight afterwards is still refused for a few seconds.
            & $deleteObject "/identity/conditionalAccess/namedLocations/$($location.id)" 'NamedLocation' `
                $location.displayName $location.id 'referenced by one or more Conditional Access policies|marked as a Trusted location'
        }
    }

    # --- 3. Licences --------------------------------------------------------------------
    # Before groups, and not optional if groups are being removed: Entra refuses to delete a
    # group that still holds one.
    if ((& $shouldRun 'Licenses') -or (& $shouldRun 'Groups')) {
        Write-TestProgress -Activity 'Removing environment' -Status 'Licences' -PercentComplete 25 -ShowProgress:$ShowProgress
        foreach ($group in (Get-EntraSeededObject -Type Groups -Connection $connection)) {
            $skuIds = @($group.assignedLicenses | ForEach-Object { $_.skuId } | Where-Object { $_ })
            if (-not $skuIds) { continue }

            if (-not $PSCmdlet.ShouldProcess($group.displayName, "Remove $($skuIds.Count) licence(s)")) { continue }
            try {
                Invoke-EntraRequest -Method POST -Path "/groups/$($group.id)/assignLicense" -RetryOnNotFound -Connection $connection -Body @{
                    addLicenses    = @()
                    removeLicenses = $skuIds
                } | Out-Null
                & $record 'GroupLicense' $group.displayName $group.id 'Removed' "$($skuIds.Count) SKU(s)"
                Write-Verbose "Removed $($skuIds.Count) licence(s) from '$($group.displayName)'"
            }
            catch {
                & $record 'GroupLicense' $group.displayName $group.id 'Failed' $_.Exception.Message
                Write-Warning ("Could not remove licences from '$($group.displayName)': $($_.Exception.Message). " +
                    "Deleting the group will fail until they are gone.")
            }
        }

        # Group licence removal is asynchronous. Without this the group delete below races it
        # and fails on exactly the group the module just un-licensed.
        if (-not $WhatIfPreference -and $removed.Where({ $_.Type -eq 'GroupLicense' }, 'First')) {
            Write-Verbose 'Waiting for group licence removal to settle before deleting groups'
            Start-Sleep -Seconds 20
        }
    }

    # --- 4. Applications and their service principals ------------------------------------
    if (& $shouldRun 'Applications') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Applications' -PercentComplete 45 -ShowProgress:$ShowProgress

        # Service principals first. Deleting the application removes its service principal
        # anyway, but doing it explicitly means an interrupted run never leaves an orphaned
        # enterprise application behind with nothing to delete it from.
        foreach ($principal in (Get-EntraSeededObject -Type ServicePrincipals -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($principal.displayName, 'Delete service principal')) { continue }
            & $deleteObject "/servicePrincipals/$($principal.id)" 'ServicePrincipal' $principal.displayName $principal.id
        }
        foreach ($application in (Get-EntraSeededObject -Type Applications -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($application.displayName, 'Delete application')) { continue }
            & $deleteObject "/applications/$($application.id)" 'Application' $application.displayName $application.id
        }
    }

    # --- 5. Devices ----------------------------------------------------------------------
    if (& $shouldRun 'Devices') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Devices' -PercentComplete 60 -ShowProgress:$ShowProgress
        & $deleteMany '/devices' 'Device' @(Get-EntraSeededObject -Type Devices -Connection $connection) 'displayName'
    }

    # --- 6. Groups -----------------------------------------------------------------------
    if (& $shouldRun 'Groups') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Groups' -PercentComplete 75 -ShowProgress:$ShowProgress
        & $deleteMany '/groups' 'Group' @(Get-EntraSeededObject -Type Groups -Connection $connection) 'displayName'
    }

    # --- 7. Users ------------------------------------------------------------------------
    if (& $shouldRun 'Users') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Users' -PercentComplete 88 -ShowProgress:$ShowProgress
        & $deleteMany '/users' 'User' @(Get-EntraSeededObject -Type Users -Connection $connection) 'userPrincipalName'
    }

    # --- 8. Administrative units -----------------------------------------------------------
    # Genuinely last among the directory objects. A unit is a container rather than a parent -
    # verified live, deleting one leaves every member in place - so removing it first would
    # discard the authoritative record of what to delete and leave teardown guessing from
    # names alone.
    if (& $shouldRun 'AdministrativeUnits') {
        Write-TestProgress -Activity 'Removing environment' -Status 'Administrative units' -PercentComplete 92 -ShowProgress:$ShowProgress
        foreach ($unit in (Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection)) {
            if (-not $PSCmdlet.ShouldProcess($unit.displayName, 'Delete administrative unit')) { continue }
            & $deleteObject "/directory/administrativeUnits/$($unit.id)" 'AdministrativeUnit' $unit.displayName $unit.id
        }
    }

    # --- 8b. The bootstrapped service app ------------------------------------------------
    # Never swept up with everything else, and opt-in even here. This is the credential the
    # module authenticates with: removing it as part of an ordinary teardown would sever the
    # connection mid-run and leave whatever had not been deleted yet unreachable. It goes last
    # of all the directory objects, and only when explicitly asked for.
    if ($RemoveServiceApp) {
        Write-TestProgress -Activity 'Removing environment' -Status 'Bootstrapped service app' -PercentComplete 94 -ShowProgress:$ShowProgress

        $serviceApps = @()
        try {
            $serviceApps = @(Invoke-EntraRequest -Method GET -Path '/applications' -Connection $connection `
                    -Paginate -ConsistencyLevel -Query @{
                        '$filter' = "startswith(displayName,'$($marker.Prefix)')"
                        '$select' = 'id,appId,displayName,tags'
                    }) | Where-Object { @($_.tags) -contains 'EntraEnvironmentServiceApp' }
        }
        catch {
            Write-Warning "Could not look for the bootstrapped service app: $($_.Exception.Message)"
        }

        foreach ($serviceApp in $serviceApps) {
            if (-not $PSCmdlet.ShouldProcess($serviceApp.displayName,
                    'Delete the service app THIS MODULE AUTHENTICATES WITH')) { continue }

            try {
                foreach ($principal in @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $connection `
                            -Paginate -ConsistencyLevel -Query @{ '$filter' = "appId eq '$($serviceApp.appId)'"; '$select' = 'id' })) {
                    & $deleteObject "/servicePrincipals/$($principal.id)" 'ServiceAppPrincipal' $serviceApp.displayName $principal.id
                }
            }
            catch {
                Write-Warning "Could not remove the service app's principal: $($_.Exception.Message)"
            }

            & $deleteObject "/applications/$($serviceApp.id)" 'ServiceApp' $serviceApp.displayName $serviceApp.id

            Write-Warning ("Removed '$($serviceApp.displayName)'. The credential this session is using no longer " +
                "exists; reconnect with -Interactive and run New-EntraServiceApp to bootstrap again.")
        }
    }

    # --- 9. Recycle bin ------------------------------------------------------------------
    if ($PurgeRecycleBin) {
        Write-TestProgress -Activity 'Removing environment' -Status 'Purging recycle bin' -PercentComplete 95 -ShowProgress:$ShowProgress

        # The bin is read after a pause, because an object deleted seconds ago has not
        # necessarily appeared in it yet, and purging a bin that looks empty leaves the group
        # names reserved for the thirty days this switch exists to avoid.
        if (-not $WhatIfPreference) {
            Write-Verbose 'Waiting for deleted objects to appear in the recycle bin'
            Start-Sleep -Seconds 20
        }

        foreach ($type in 'user', 'group', 'application') {
            $binned = @()
            try {
                $binned = @((Invoke-EntraRequest -Method GET -Path "/directory/deletedItems/microsoft.graph.$type" -Connection $connection -Paginate))
            }
            catch {
                Write-Warning "Could not read the $type recycle bin: $($_.Exception.Message)"
                continue
            }

            foreach ($item in $binned) {
                # A soft-deleted user's UPN is rewritten with its id prefixed, so the prefix
                # is no longer at the start of it. Both the display name and a contains match
                # on the UPN are checked, and the tag is accepted as proof on its own.
                #
                # The third clause is for the B2B guests, and neither of the first two can
                # reach them: seeded people carry real display names rather than prefixed ones,
                # and a B2B UPN always lands on the tenant's initial onmicrosoft.com domain
                # rather than on the seed domain. Connect with -UpnSuffix naming a custom
                # verified domain and the second clause misses every guest, which leaves them
                # in the bin for thirty days with their names still reserved. This is the same
                # widening Get-EntraSeededObject makes for the same reason, and it is safe for
                # the same reason: #EXT# is minted by Entra, so a genuine partner guest would
                # need an email address that literally begins with the seed prefix.
                $isOurs =
                    ($item.displayName -and $item.displayName.StartsWith($marker.Prefix, [StringComparison]::OrdinalIgnoreCase)) -or
                    ($item.userPrincipalName -and $item.userPrincipalName -like "*$($marker.Prefix)*@$($marker.UpnSuffix)") -or
                    ($item.userPrincipalName -and $item.userPrincipalName -like "*$($marker.Prefix)*#EXT#@*")

                if (-not $isOurs) {
                    Write-Verbose "Leaving $type '$($item.displayName)' in the recycle bin; it is not ours."
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess($item.displayName, "Permanently purge $type from the recycle bin")) { continue }
                & $deleteObject "/directory/deletedItems/$($item.id)" "Purged$type" $item.displayName $item.id
            }
        }
    }

    Write-TestProgress -Activity 'Removing environment' -Completed -ShowProgress:$ShowProgress

    $result = [PSCustomObject]@{
        PSTypeName   = 'EntraTeardownResult'
        TenantId     = $connection.TenantId
        TenantName   = $connection.TenantName
        Prefix       = $marker.Prefix
        RemovedCount = $removed.Count
        SkippedCount = $skipped.Count
        Removed      = $removed.ToArray()
        Skipped      = $skipped.ToArray()
    }

    if ($skipped.Count -gt 0) {
        Write-Warning ("$($skipped.Count) object(s) were not removed. Inspect the Skipped collection with " +
            "-PassThru to see why.")
    }

    Write-Verbose "Teardown complete: $($removed.Count) removed, $($skipped.Count) not removed"

    if ($PassThru) { return $result }
}
