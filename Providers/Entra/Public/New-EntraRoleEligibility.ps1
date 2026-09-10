function New-EntraRoleEligibility {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Makes seeded principals *eligible* for the seeded custom roles, and never active in them
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraRoleEligibility')]
    param(
        [Parameter()]
        [string[]]$EligibilityKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraRoleEligibilities')
    if ($EligibilityKey) {
        $definitions = @($definitions | Where-Object { $EligibilityKey -contains $_.Key })
        $missing = @($EligibilityKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for eligibility key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    # Resolved once. Both collections are small, and asking per row would cost a call each.
    $roleDefinitions = @(Get-EntraSeededObject -Type DirectoryRoles -Connection $connection)
    if ($roleDefinitions.Count -eq 0) {
        Write-Warning ('No seeded custom role definitions exist, so there is nothing to be eligible for. ' +
            'Run New-EntraDirectoryRole first.')
        return
    }

    $roleSeed = @(Get-EntraSeedData -Name 'EntraDirectoryRoles')
    $units = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection)

    # Existing eligibilities, read once so a re-run is quiet rather than a wall of conflicts.
    $existing = @()
    try {
        $existing = @(Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                -Path '/roleManagement/directory/roleEligibilitySchedules' `
                -Query @{ '$select' = 'id,principalId,roleDefinitionId,directoryScopeId' })
    }
    catch {
        Write-Verbose "Could not read the existing eligibility schedules: $($_.Exception.Message)"
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $principalCache = @{}
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        Write-TestProgress -Activity 'Seeding role eligibilities' -Status $definition.Key `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        # --- The role, which must be one this module created -----------------------------
        $roleRow = $roleSeed | Where-Object { $_.Key -eq $definition.RoleKey } | Select-Object -First 1
        if (-not $roleRow) {
            Write-Warning "Eligibility '$($definition.Key)' names role key '$($definition.RoleKey)', which has no seed definition. Skipping it."
            continue
        }

        $roleName = '{0}{1}' -f $marker.Prefix, $roleRow.DisplayName
        $role = $roleDefinitions | Where-Object { $_.displayName -eq $roleName } | Select-Object -First 1
        if (-not $role) {
            Write-Warning ("Eligibility '$($definition.Key)' names role '$roleName', which does not exist as a seeded " +
                'custom role. Skipping it - this function will not make anybody eligible for a role it did not create.')
            continue
        }

        # --- The principal ---------------------------------------------------------------
        $principalKind = if ($definition.PrincipalKind -eq 'Group') { 'Group' } else { 'User' }
        $principalId = Resolve-EntraSeededId -Key $definition.PrincipalKey -Kind $principalKind `
            -Cache $principalCache -Connection $connection

        if (-not $principalId) {
            Write-Warning ("Eligibility '$($definition.Key)' names $($principalKind.ToLower()) " +
                "'$($definition.PrincipalKey)', which does not exist. Skipping it.")
            continue
        }

        # --- The scope -------------------------------------------------------------------
        $scope = '/'
        if ($definition.ScopeKind -eq 'AdministrativeUnit') {
            $unitName = '{0}{1}' -f $marker.Prefix, $definition.ScopeUnit
            $unit = $units | Where-Object { $_.displayName -eq $unitName } | Select-Object -First 1
            if (-not $unit) {
                Write-Warning ("Eligibility '$($definition.Key)' is scoped to administrative unit '$unitName', which " +
                    'does not exist. Skipping it rather than widening the scope to the whole directory.')
                continue
            }
            $scope = "/administrativeUnits/$($unit.id)"
        }

        $already = $existing | Where-Object {
            $_.principalId -eq $principalId -and $_.roleDefinitionId -eq $role.id -and $_.directoryScopeId -eq $scope
        } | Select-Object -First 1

        $describe = '{0} eligible for {1} at {2}' -f $definition.PrincipalKey, $roleName, $scope

        if ($already) {
            Write-Verbose "Eligibility already exists: $describe"
            $created.Add([PSCustomObject]@{
                    PSTypeName = 'EntraRoleEligibility'
                    Key        = $definition.Key
                    Id         = $already.id
                    Role       = $roleName
                    Principal  = $definition.PrincipalKey
                    Kind       = $principalKind
                    Scope      = $scope
                    Purpose    = $definition.Purpose
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($describe, 'Create eligible role schedule')) { continue }

        # TryParse writes zero into its target when it fails, so it cannot be given the variable
        # holding the default - a bad row would silently become a zero-day eligibility.
        $days = 30
        $parsed = 0
        if ($definition.DurationDays -and [int]::TryParse($definition.DurationDays, [ref]$parsed) -and $parsed -gt 0) {
            $days = $parsed
        }

        try {
            # adminAssign on roleEligibilityScheduleRequests. The active counterpart lives at
            # roleAssignmentScheduleRequests, and this module never posts to it.
            $request = Invoke-EntraRequest -Method POST -Connection $connection `
                -Path '/roleManagement/directory/roleEligibilityScheduleRequests' -Body @{
                action           = 'adminAssign'
                principalId      = $principalId
                roleDefinitionId = $role.id
                directoryScopeId = $scope

                # For the human reading PIM's audit view, and for nothing else. The justification
                # lives on the *request*, not on the schedule it produces - a
                # unifiedRoleEligibilitySchedule exposes no such property - so teardown cannot
                # read it back and does not try. Ownership rests entirely on the role definition
                # the schedule points at, which is the one marker that survives.
                justification    = $marker.Description
                scheduleInfo     = @{
                    startDateTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    expiration    = @{
                        # afterDuration rather than noExpiration, on purpose. A lab that is
                        # never torn down stops offering the activation after this elapses.
                        type     = 'afterDuration'
                        duration = 'P{0}D' -f $days
                    }
                }
            }
        }
        catch {
            $message = $_.Exception.Message

            # An eligibility that is already there. Reached whenever the pre-read above failed -
            # it is caught to a verbose line, so a throttled read makes every row look new - and
            # a correctly seeded tenant would then report three failures for being correct.
            # New-EntraDirectoryRole and the group membership in New-EntraGuestUser both treat
            # "already there" as the ordinary answer on a re-run, and so does this.
            if ($message -match 'RoleAssignmentExists|RoleEligibilityExists|already exists|conflicting object') {
                Write-Verbose "Eligibility already exists: $describe"
                $created.Add([PSCustomObject]@{
                        PSTypeName = 'EntraRoleEligibility'
                        Key        = $definition.Key
                        Id         = $null
                        Role       = $roleName
                        Principal  = $definition.PrincipalKey
                        Kind       = $principalKind
                        Scope      = $scope
                        Purpose    = $definition.Purpose
                    })
                continue
            }

            # PIM is a P2 feature. Without the licence the create is refused, and the message
            # names the subscription rather than the request, which reads like a bug in the
            # caller unless it is said out loud.
            if ($message -match 'AadPremium|subscription|licen[cs]e|RoleAssignmentPolicy|not enabled') {
                Write-Warning ("Could not create the eligibility '$($definition.Key)': $message. Privileged Identity " +
                    'Management requires Entra ID P2 - without it the custom roles still exist, and nothing is ' +
                    'eligible for them. Skip this step with -Skip RoleEligibilities.')
            }
            else {
                Write-Warning "Could not create the eligibility '$($definition.Key)': $message"
            }
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName = 'EntraRoleEligibility'
                Key        = $definition.Key

                # targetScheduleId, not the request's own id. The POST returns a
                # roleEligibilityScheduleRequest, whose id addresses the *request* - a different
                # object at a different endpoint from the schedule it produced. Returning that
                # would make Id mean one thing on a first run and another on a re-run, where the
                # already-exists path above reports the schedule id.
                Id         = if ($request.targetScheduleId) { $request.targetScheduleId } else { $request.id }
                Role       = $roleName
                Principal  = $definition.PrincipalKey
                Kind       = $principalKind
                Scope      = $scope
                Purpose    = $definition.Purpose
            })

        Write-Verbose "Created eligibility: $describe"
    }

    Write-TestProgress -Activity 'Seeding role eligibilities' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
