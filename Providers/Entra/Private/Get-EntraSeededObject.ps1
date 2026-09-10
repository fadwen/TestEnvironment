function Get-EntraSeededObject {
    <#
    .SYNOPSIS
        Finds objects this module created, and refuses to claim anything else

    .DESCRIPTION
        This is the function teardown deletes from, so it is deliberately conservative. The
        tenant is expected to be in real use, and a deleted Entra object is recoverable only
        by somebody who notices inside thirty days.

        Ownership is established two ways, and the first is much stronger than the second:

        1. **Administrative unit membership.** Everything this module creates is placed in the
           administrative unit for its class, so the container can be asked what it holds. This
           is Entra's nearest equivalent to asking an OU for its contents, and it is
           authoritative: an object is in the unit because this module put it there, not
           because its name happens to match a pattern.
        2. **Name prefix plus a second marker**, as a fallback. Used for objects that cannot
           belong to an administrative unit at all - named locations, Conditional Access
           policies and service principals - and as a safety net for anything whose unit
           placement failed, or whose unit somebody has since deleted. Without the fallback,
           deleting the container would strand everything it used to hold.

        The two are unioned by object id, and SeedProof records which routes claimed each one,
        so a report can show whether the container or the name did the work.

        What the fallback requires differs by type, because the types differ in what they can
        carry. Users need the prefixed UPN on the seed domain OR the seed tag; groups and
        applications need the name prefix AND a second marker, because a real object could
        plausibly satisfy either alone. Devices, named locations and policies have only their
        name, which is enough only because the prefix must end in a separator - ENTRALAB-
        cannot match a genuine object called ENTRALABORATORY.

        Nothing here deletes. The caller decides that, which keeps the dangerous half of
        teardown reviewable in one place.

    .PARAMETER Type
        Which directory object type to search for

    .PARAMETER SkipUnitLookup
        Ignores administrative unit membership and uses only the name-based fallback. Used by
        teardown after the units themselves have been removed.

    .PARAMETER Connection
        Connection to use instead of the module's active one

    .OUTPUTS
        The matching Graph objects, each with a SeedProof property naming why it was claimed.

    .EXAMPLE
        PS> Get-EntraSeededObject -Type Users

        DESCRIPTION: Finds every seeded user, and no others
        OUTPUT: The user objects, each carrying a SeedProof property
        USE CASE: Called by Remove-EntraEnvironment and by the report

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Users', 'Groups', 'Devices', 'Applications', 'ServicePrincipals',
            'NamedLocations', 'ConditionalAccessPolicies', 'AdministrativeUnits',
            'AuthenticationStrengths', 'DirectoryRoles', 'RoleEligibilities')]
        [string]$Type,

        [Parameter()]
        [switch]$SkipUnitLookup,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }
    $marker = Get-EntraSeedMarker -Connection $Connection
    $prefix = $marker.Prefix

    # How each type is described. UnitKey is the administrative unit that holds it, or $null
    # for the types that cannot belong to one.
    $shape = @{
        Users             = @{ UnitKey = 'Users'; Graph = 'user'; Path = '/users'
            Select = 'id,displayName,userPrincipalName,accountEnabled,userType,externalUserState,mail,department,jobTitle,usageLocation,employeeId,employeeType,companyName,onPremisesExtensionAttributes,assignedLicenses,createdDateTime'
        }
        Groups            = @{ UnitKey = 'Groups'; Graph = 'group'; Path = '/groups'
            Select = 'id,displayName,description,mailNickname,groupTypes,securityEnabled,mailEnabled,membershipRule,isAssignableToRole,assignedLicenses,createdDateTime'
        }
        Devices           = @{ UnitKey = 'Devices'; Graph = 'device'; Path = '/devices'
            Select = 'id,deviceId,displayName,operatingSystem,operatingSystemVersion,isCompliant,isManaged,accountEnabled,trustType,profileType'
        }
        Applications      = @{ UnitKey = 'Applications'; Graph = 'application'; Path = '/applications'
            Select = 'id,appId,displayName,tags,notes,signInAudience,createdDateTime'
        }
        ServicePrincipals = @{ UnitKey = $null; Graph = 'servicePrincipal'; Path = '/servicePrincipals'
            Select = 'id,appId,displayName,tags,servicePrincipalType,accountEnabled'
        }
    }

    $claimed = @{}

    $claim = {
        param($Object, $Route)
        if (-not $Object -or -not $Object.id) { return }
        if ($claimed.ContainsKey($Object.id)) {
            $existing = $claimed[$Object.id]
            if ($existing.SeedProof -notlike "*$Route*") {
                $existing.SeedProof = ($existing.SeedProof, $Route -join '+')
            }
            return
        }
        $claimed[$Object.id] = ($Object | Add-Member -NotePropertyName SeedProof -NotePropertyValue $Route -Force -PassThru)
    }

    # ---------------------------------------------------------------------------------
    # The administrative units themselves
    # ---------------------------------------------------------------------------------
    if ($Type -eq 'AdministrativeUnits') {
        # There is no startswith filter on this collection, so it is listed and filtered here.
        # A tenant holds tens of administrative units at most, so this costs one call.
        $all = @((Invoke-EntraRequest -Method GET -Path '/directory/administrativeUnits' -Connection $Connection -Paginate))
        foreach ($candidate in $all) {
            if (-not ($candidate.displayName -and $candidate.displayName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) { continue }
            if (-not ($candidate.description -and $candidate.description -like "*$($marker.Tag)*")) {
                Write-Warning ("Administrative unit '$($candidate.displayName)' starts with the seed prefix but its " +
                    "description does not carry $($marker.Tag). Leaving it alone.")
                continue
            }
            & $claim $candidate 'name+description'
        }
        $result = @($claimed.Values)
        Write-Verbose "Found $($result.Count) seeded administrative unit(s)"
        return $result
    }

    # ---------------------------------------------------------------------------------
    # Route 1: the container
    # ---------------------------------------------------------------------------------
    $unitKey = if ($shape.ContainsKey($Type)) { $shape[$Type].UnitKey } else { $null }

    if ($unitKey -and -not $SkipUnitLookup) {
        $units = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $Connection)
        $unit = $units | Where-Object { $_.displayName -eq ('{0}{1}' -f $prefix, $unitKey) } | Select-Object -First 1

        if ($unit) {
            try {
                # The typed member form, so Graph returns full objects of the right kind
                # rather than bare directoryObject references needing a second lookup each.
                $members = @(Invoke-EntraRequest -Method GET -Connection $Connection -Paginate `
                        -Path "/directory/administrativeUnits/$($unit.id)/members/microsoft.graph.$($shape[$Type].Graph)" `
                        -Query @{ '$select' = $shape[$Type].Select })

                foreach ($member in $members) { & $claim $member 'unit' }
                Write-Verbose "Administrative unit '$($unit.displayName)' holds $($members.Count) $Type"
            }
            catch {
                Write-Warning ("Could not read the members of '$($unit.displayName)': $($_.Exception.Message). " +
                    "Falling back to matching on the name prefix.")
            }
        }
        else {
            Write-Verbose "No administrative unit for $Type; using the name-based fallback only."
        }
    }

    # ---------------------------------------------------------------------------------
    # Route 2: the name-based fallback
    # ---------------------------------------------------------------------------------
    switch ($Type) {

        'Users' {
            # Two queries unioned: the UPN one is the reliable marker, the displayName one
            # catches a user whose UPN was changed but whose name still carries the prefix.
            $candidates = @()
            foreach ($property in 'userPrincipalName', 'displayName') {
                $candidates += @(Invoke-EntraRequest -Method GET -Path '/users' -Connection $Connection -Paginate -ConsistencyLevel `
                        -Query @{ '$filter' = "startswith($property,'$prefix')"; '$select' = $shape.Users.Select })
            }

            foreach ($candidate in $candidates) {
                $prefixed = $candidate.userPrincipalName -and
                    $candidate.userPrincipalName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)

                # A B2B guest never lands on the seed domain. Entra mints its UPN from the
                # invited address and always puts it on the tenant's initial onmicrosoft.com
                # domain, so ENTRALAB-gmember@example.com becomes
                # ENTRALAB-gmember_example.com#EXT#@tenant.onmicrosoft.com. Requiring the seed
                # suffix would leave every guest unclaimed whenever -UpnSuffix names a custom
                # domain, which is the case teardown must not miss. The #EXT# marker is what
                # makes this safe to widen: it is minted by Entra and cannot be typed by hand.
                $upnMatch = $prefixed -and (
                    $candidate.userPrincipalName.EndsWith("@$($marker.UpnSuffix)", [StringComparison]::OrdinalIgnoreCase) -or
                    $candidate.userPrincipalName -like '*#EXT#@*'
                )

                $tagMatch = $candidate.onPremisesExtensionAttributes -and
                    $candidate.onPremisesExtensionAttributes.extensionAttribute15 -eq $marker.Tag

                if (-not ($upnMatch -or $tagMatch)) {
                    if (-not $claimed.ContainsKey($candidate.id)) {
                        Write-Verbose "Skipping user $($candidate.userPrincipalName): name matched the prefix but ownership is unproven."
                    }
                    continue
                }

                $route = @(if ($upnMatch) { 'upn' }; if ($tagMatch) { 'tag' }) -join '+'
                & $claim $candidate $route
            }
        }

        'Groups' {
            $candidates = @(Invoke-EntraRequest -Method GET -Path '/groups' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "startswith(displayName,'$prefix')"; '$select' = $shape.Groups.Select })

            foreach ($candidate in $candidates) {
                if (-not ($candidate.description -and $candidate.description -like "*$($marker.Tag)*")) {
                    if (-not $claimed.ContainsKey($candidate.id)) {
                        Write-Warning ("Group '$($candidate.displayName)' starts with the seed prefix but its " +
                            "description does not carry $($marker.Tag). Leaving it alone.")
                    }
                    continue
                }
                & $claim $candidate 'name+description'
            }
        }

        'Applications' {
            $candidates = @(Invoke-EntraRequest -Method GET -Path '/applications' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "startswith(displayName,'$prefix')"; '$select' = $shape.Applications.Select })

            foreach ($candidate in $candidates) {
                # The bootstrapped service app is excluded from ordinary discovery, and this is
                # the single most important exclusion in the module. It carries the seed prefix
                # and the seed tag like everything else, so without this teardown would delete
                # the credential it is authenticating with - halfway through, leaving the rest
                # of the environment behind and no way to reach it.
                if (@($candidate.tags) -contains 'EntraEnvironmentServiceApp') {
                    Write-Verbose "Skipping the bootstrapped service app '$($candidate.displayName)'"
                    continue
                }

                if (@($candidate.tags) -notcontains $marker.Tag) {
                    if (-not $claimed.ContainsKey($candidate.id)) {
                        Write-Warning ("Application '$($candidate.displayName)' starts with the seed prefix but is " +
                            "not tagged $($marker.Tag). Leaving it alone.")
                    }
                    continue
                }
                & $claim $candidate 'name+tag'
            }
        }

        'ServicePrincipals' {
            # Cannot belong to an administrative unit, so the tag is the only corroboration.
            $candidates = @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "startswith(displayName,'$prefix')"; '$select' = $shape.ServicePrincipals.Select })

            foreach ($candidate in $candidates) {
                # Same exclusion as the application above, for the same reason.
                if (@($candidate.tags) -contains 'EntraEnvironmentServiceApp') {
                    Write-Verbose "Skipping the bootstrapped service principal '$($candidate.displayName)'"
                    continue
                }

                if (@($candidate.tags) -notcontains $marker.Tag) {
                    Write-Warning ("Service principal '$($candidate.displayName)' starts with the seed prefix but is " +
                        "not tagged $($marker.Tag). Leaving it alone.")
                    continue
                }
                & $claim $candidate 'name+tag'
            }
        }

        'Devices' {
            # Devices carry no second marker that survives creation, so the prefix is all
            # there is. It is enough only because the prefix must end in a separator.
            $candidates = @(Invoke-EntraRequest -Method GET -Path '/devices' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "startswith(displayName,'$prefix')"; '$select' = $shape.Devices.Select })
            foreach ($candidate in $candidates) { & $claim $candidate 'name' }
        }

        'NamedLocations' {
            # The Conditional Access endpoints support no startswith filter, so these are
            # listed and filtered here. Both collections are small by nature.
            $all = @((Invoke-EntraRequest -Method GET -Path '/identity/conditionalAccess/namedLocations' -Connection $Connection).value)
            foreach ($candidate in $all) {
                if (-not ($candidate.displayName -and $candidate.displayName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) { continue }
                & $claim $candidate 'name'
            }
        }

        'ConditionalAccessPolicies' {
            $all = @((Invoke-EntraRequest -Method GET -Path '/identity/conditionalAccess/policies' -Connection $Connection).value)
            foreach ($candidate in $all) {
                if (-not ($candidate.displayName -and $candidate.displayName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) { continue }
                & $claim $candidate 'name'
            }
        }

        'AuthenticationStrengths' {
            # Built-in strengths live in the same collection as custom ones and cannot be
            # deleted, so policyType is checked as well as the name. A built-in that somebody
            # renamed to match the prefix would otherwise be attempted and fail every run.
            $all = @((Invoke-EntraRequest -Method GET -Path '/identity/conditionalAccess/authenticationStrength/policies' -Connection $Connection).value)
            foreach ($candidate in $all) {
                if (-not ($candidate.displayName -and $candidate.displayName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) { continue }
                if ($candidate.policyType -ne 'custom') {
                    Write-Warning ("Authentication strength '$($candidate.displayName)' starts with the seed prefix " +
                        "but is built in and cannot be removed. Leaving it alone.")
                    continue
                }
                & $claim $candidate 'name'
            }
        }

        'DirectoryRoles' {
            # Only custom definitions. isBuiltIn separates the roles Entra ships from the ones
            # this module created, and a built-in cannot be deleted at all.
            $all = @(Invoke-EntraRequest -Method GET -Path '/roleManagement/directory/roleDefinitions' -Connection $Connection -Paginate `
                    -Query @{ '$select' = 'id,displayName,description,isBuiltIn,isEnabled,rolePermissions' })
            foreach ($candidate in $all) {
                if (-not ($candidate.displayName -and $candidate.displayName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) { continue }
                if ($candidate.isBuiltIn) {
                    Write-Warning ("Directory role '$($candidate.displayName)' starts with the seed prefix but is " +
                        "built in and cannot be removed. Leaving it alone.")
                    continue
                }
                & $claim $candidate 'name'
            }
        }

        'RoleEligibilities' {
            # An eligibility schedule has no name of its own and carries no writable field to
            # tag, so neither marker this module normally uses applies to it. What it does have
            # is a roleDefinitionId, and the role definitions are seeded objects already proven
            # by the branch above. Ownership is therefore inherited: an eligibility is this
            # module's if and only if it points at a custom role this module created. That is
            # stronger than a name match - a built-in role can never satisfy it, so there is no
            # path from here to deleting somebody's real Global Administrator eligibility.
            #
            # It is also the only single-route type in this function, and the route is a
            # borrowed one. Delete the role definitions and the eligibilities become
            # unidentifiable, which is why the read below refuses to fail quietly and why
            # teardown keeps the definitions when it does.
            $seededRoles = @(Get-EntraSeededObject -Type DirectoryRoles -Connection $Connection)
            if ($seededRoles.Count -eq 0) {
                Write-Verbose 'No seeded custom roles exist, so no eligibility can belong to this module.'
                break
            }

            $roleNameById = @{}
            foreach ($role in $seededRoles) { $roleNameById[$role.id] = $role.displayName }

            $all = @()
            try {
                $all = @(Invoke-EntraRequest -Method GET -Connection $Connection -Paginate `
                        -Path '/roleManagement/directory/roleEligibilitySchedules' `
                        -Query @{ '$select' = 'id,principalId,roleDefinitionId,directoryScopeId,status' })
            }
            catch {
                # Warned rather than passed over, and the distinction matters more here than
                # anywhere else in this function. Every other type has a name or tag fallback,
                # so a failed read costs one route out of two. An eligibility has neither: its
                # only proof of ownership is the role definition it points at, and teardown
                # deletes those moments later. A read that fails silently therefore reads as
                # "there are none", withdraws nothing, and lets the definitions go - after
                # which no future run can identify the eligibilities at all.
                #
                # Not the same thing as a tenant without P2, which genuinely has none and
                # answers with an empty list rather than an error.
                # Rethrown as a terminating error rather than swallowed, so a caller that must
                # tell "none" from "could not tell" can. Teardown catches this and keeps the
                # role definitions; the report catches it and reports the count as unknown.
                Write-Error ("Could not read the role eligibility schedules: $($_.Exception.Message). " +
                    'They cannot be identified without the role definitions they point at, so the definitions ' +
                    'must not be deleted until this read succeeds.') -ErrorAction Stop
            }

            foreach ($candidate in $all) {
                if (-not $roleNameById.ContainsKey($candidate.roleDefinitionId)) { continue }

                # Carried so the caller can name the role without resolving it again, and so
                # teardown's ShouldProcess line reads as something a human recognises.
                $candidate | Add-Member -NotePropertyName displayName `
                    -NotePropertyValue ('{0} eligibility at {1}' -f $roleNameById[$candidate.roleDefinitionId], $candidate.directoryScopeId) -Force
                & $claim $candidate 'seeded-role'
            }
        }
    }

    $result = @($claimed.Values)
    Write-Verbose "Found $($result.Count) seeded object(s) of type $Type"
    return $result
}
