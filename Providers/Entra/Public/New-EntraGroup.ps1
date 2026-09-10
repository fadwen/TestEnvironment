function New-EntraGroup {
    <#
    .SYNOPSIS
        Creates the seeded groups defined in Data\EntraGroups.csv, and their membership

    .DESCRIPTION
        Creates around a hundred groups: a hand-designed core covering the shapes that break
        membership reporting, and bulk volume mapped from ADTestEnvironment, including the
        nesting AD's own data describes.

        The core is the part worth reading the CSV for - a three-deep nesting chain, a group
        containing only other groups, overlapping departments, dynamic membership, a Microsoft
        365 group, a role-assignable group and a deliberately empty one. The bulk is what makes
        a transitive expansion expensive enough to be worth measuring.

        Only two of Entra's four group flavours can be created here, and that is a hard limit
        rather than an omission. Verified against a live tenant: Graph refuses both distribution
        lists and mail-enabled security groups with "Cannot Create a mail-enabled security
        groups and or distribution list", whatever combination of mailEnabled, securityEnabled
        and groupTypes is sent. Exchange Online PowerShell is the only way to make those two.

        Groups are created in one batched phase and their membership applied in another, for
        the same reason users get their managers separately: a parent can appear above its
        children in the CSV, and a nesting chain cannot be built until every link exists.

        Dynamic groups are created with their rule already on, and every rule is required to
        scope itself to the seed prefix. That is not defensive tidiness. The first live run
        used (user.userType -eq "Guest") and Entra immediately put two real external accounts
        into a seeded group.

    .PARAMETER GroupKey
        Creates only the named groups, by their Key column. Defaults to all of them.

    .PARAMETER Tier
        Creates only Core rows (the designed shapes) or only Bulk rows (the volume).

    .PARAMETER SkipMembership
        Creates the groups but assigns no members and builds no nesting

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created groups

    .OUTPUTS
        EntraGroup[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraGroup

        DESCRIPTION: Creates every seeded group and wires up its membership
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment

    .EXAMPLE
        PS> New-EntraGroup -GroupKey nested-tier1, nested-tier2, nested-tier3 -PassThru

        DESCRIPTION: Rebuilds just the nesting chain
        OUTPUT: The three group objects
        USE CASE: Testing transitive membership expansion against a known-depth chain

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraGroup')]
    param(
        [Parameter()]
        [string[]]$GroupKey,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$SkipMembership,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraGroups')
    if ($Tier) { $definitions = @($definitions | Where-Object { $Tier -contains $_.Tier }) }
    if ($GroupKey) {
        $definitions = @($definitions | Where-Object { $GroupKey -contains $_.Key })
        $missing = @($GroupKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for group key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    Write-Verbose "Creating $($definitions.Count) group(s)"

    # Entra places no uniqueness constraint on a group's displayName, so re-running would
    # cheerfully create a second copy of every group - verified live, a re-run produced 103
    # duplicates. Users and devices collide on their own natural keys (userPrincipalName and
    # alternativeSecurityIds) and are idempotent for free; groups have to be checked.
    $existingByName = @{}
    foreach ($group in (Get-EntraSeededObject -Type Groups -Connection $connection)) {
        $existingByName[$group.displayName] = $group
    }
    if ($existingByName.Count -gt 0) {
        Write-Verbose "$($existingByName.Count) seeded group(s) already exist and will be reused"
    }

    # --- Phase 1: create ---------------------------------------------------------------
    $createRequests = [System.Collections.Generic.List[object]]::new()
    $definitionByKey = @{}
    $idByKey = @{}

    foreach ($definition in $definitions) {
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName
        $definitionByKey[$definition.Key] = $definition

        if ($existingByName.ContainsKey($displayName)) {
            Write-Verbose "Group '$displayName' already exists; reusing it"
            $idByKey[$definition.Key] = $existingByName[$displayName].id
            continue
        }

        # Validated before the switch rather than in a default branch. 'continue' inside a
        # PowerShell switch breaks out of the SWITCH, not the enclosing foreach, so rejecting
        # an unsupported kind from a default case falls straight through and creates it anyway.
        if ($definition.GroupKind -notin @('Security', 'Unified')) {
            Write-Error ("Group '$($definition.Key)' declares GroupKind '$($definition.GroupKind)', which " +
                "Graph cannot create. Only Security and Unified are possible; distribution lists and " +
                "mail-enabled security groups require Exchange Online PowerShell.") -ErrorAction Continue
            continue
        }

        $body = @{
            displayName  = $displayName
            # Not decoration. This carries the seed tag, and teardown requires both it and the
            # name prefix before it will delete a group found outside the container.
            description  = $marker.Description
            mailNickname = ('{0}{1}' -f $marker.Prefix, $definition.Key) -replace '[^A-Za-z0-9]', ''
        }

        switch ($definition.GroupKind) {
            'Unified' {
                $body.groupTypes = @('Unified')
                $body.mailEnabled = $true
                $body.securityEnabled = $false
            }
            'Security' {
                $body.groupTypes = @()
                $body.mailEnabled = $false
                $body.securityEnabled = $true
            }
        }

        if ($definition.MembershipType -eq 'Dynamic') {
            if (-not $definition.MembershipRule) {
                Write-Error "Group '$($definition.Key)' is marked Dynamic but carries no MembershipRule." -ErrorAction Continue
                continue
            }

            # DynamicMembership is added to whatever groupTypes the flavour already needs, not
            # substituted for it: a dynamic Microsoft 365 group is both.
            $body.groupTypes = @($body.groupTypes + 'DynamicMembership')

            $rule = $definition.MembershipRule.Replace('{Prefix}', $marker.Prefix)
            if ($rule -notlike "*$($marker.Prefix)*") {
                Write-Error ("Dynamic group '$($definition.Key)' has a membership rule that does not scope itself " +
                    "to the seed prefix, so it would match objects this module did not create. Refusing to " +
                    "create it. Rule: $rule") -ErrorAction Continue
                continue
            }

            $body.membershipRule = $rule
            $body.membershipRuleProcessingState = 'On'
        }

        if ([bool]::Parse($definition.IsAssignableToRole)) {
            # Immutable after creation, and it changes how the group is protected: only
            # Privileged Role Administrators can manage it afterwards.
            $body.isAssignableToRole = $true
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create group')) { continue }

        $createRequests.Add([PSCustomObject]@{
                Reference = $definition.Key
                Method    = 'POST'
                Url       = '/groups'
                Body      = $body
            })
    }

    if ($createRequests.Count -gt 0) {
        $createResults = @(Invoke-EntraBatch -Request $createRequests.ToArray() -Connection $connection `
                -Activity 'Seeding groups' -ShowProgress:$ShowProgress)

        $newCount = 0
        foreach ($result in $createResults) {
            if ($result.Success -and $result.Body.id) { $idByKey[$result.Reference] = $result.Body.id; $newCount++ }
            else { Write-Warning "Could not create group '$($result.Reference)': $($result.Error)" }
        }
        Write-Verbose "Created $newCount of $($createRequests.Count) new group(s)"
    }

    if ($idByKey.Count -eq 0) {
        Write-TestProgress -Activity 'Seeding groups' -Completed -ShowProgress:$ShowProgress
        return
    }

    # --- Phase 2: membership -----------------------------------------------------------
    if (-not $SkipMembership -and $idByKey.Count -gt 0) {
        # Users are resolved once for the whole step rather than per group. At this volume the
        # same person appears in a dozen groups, and a lookup each would dominate the phase.
        $userIdByKey = @{}
        foreach ($user in (Get-EntraSeededObject -Type Users -Connection $connection)) {
            $upn = $user.userPrincipalName
            if ($upn -match "^$([regex]::Escape($marker.Prefix))(?<key>.+?)@") {
                $userIdByKey[$Matches['key']] = $user.id
            }
        }
        Write-Verbose "Resolved $($userIdByKey.Count) seeded user(s) for membership"

        $memberRequests = [System.Collections.Generic.List[object]]::new()
        $missingMembers = 0

        foreach ($key in $idByKey.Keys) {
            $definition = $definitionByKey[$key]

            # Entra owns the membership of a dynamic group. Adding a member by hand is
            # rejected, and would be overwritten by the next evaluation if it were not.
            if ($definition.MembershipType -eq 'Dynamic') { continue }

            $memberIds = @(
                foreach ($member in ($definition.Members -split ';' | Where-Object { $_ })) {
                    $trimmed = $member.Trim()
                    if ($userIdByKey.ContainsKey($trimmed)) { $userIdByKey[$trimmed] } else { $missingMembers++ }
                }
                foreach ($member in ($definition.MemberGroups -split ';' | Where-Object { $_ })) {
                    $trimmed = $member.Trim()
                    if ($idByKey.ContainsKey($trimmed)) { $idByKey[$trimmed] } else { $missingMembers++ }
                }
            )

            foreach ($memberId in $memberIds) {
                $memberRequests.Add([PSCustomObject]@{
                        Reference = "$key/$memberId"
                        Method    = 'POST'
                        Url       = "/groups/$($idByKey[$key])/members/`$ref"
                        Body      = @{ '@odata.id' = "$($connection.GraphBaseUri)/v1.0/directoryObjects/$memberId" }
                    })
            }
        }

        if ($missingMembers -gt 0) {
            Write-Warning "$missingMembers group member reference(s) named an object that does not exist and were skipped."
        }

        if ($memberRequests.Count -gt 0) {
            Write-Verbose "Adding $($memberRequests.Count) group membership(s)"
            $memberResults = @(Invoke-EntraBatch -Request $memberRequests.ToArray() -Connection $connection `
                    -RetryOnNotFound -Activity 'Adding group members' -ShowProgress:$ShowProgress)

            $duplicate = 'already exist|added object references already exist|A conflicting object'
            $failed = @($memberResults | Where-Object { -not $_.Success -and $_.Error -notmatch $duplicate })
            if ($failed.Count -gt 0) {
                Write-Warning "$($failed.Count) group membership(s) could not be added. First error: $($failed[0].Error)"
            }
        }
    }

    # --- Phase 3: containment ----------------------------------------------------------
    if ($idByKey.Count -gt 0) {
        $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
            Where-Object { $_.displayName -eq ('{0}Groups' -f $marker.Prefix) } | Select-Object -First 1

        if ($unit) {
            $placed = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($idByKey.Values) -Connection $connection `
                -Activity 'Placing groups in their administrative unit' -ShowProgress:$ShowProgress
            Write-Verbose "Placed $placed group(s) in '$($unit.displayName)'"
        }
        else {
            Write-Warning ("No $($marker.Prefix)Groups administrative unit exists, so the created groups are not " +
                "contained. Run New-EntraAdministrativeUnit first.")
        }
    }

    Write-TestProgress -Activity 'Seeding groups' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) {
        return @(foreach ($key in $idByKey.Keys) {
                $definition = $definitionByKey[$key]
                [PSCustomObject]@{
                    PSTypeName     = 'EntraGroup'
                    Key            = $key
                    Id             = $idByKey[$key]
                    DisplayName    = '{0}{1}' -f $marker.Prefix, $definition.DisplayName
                    GroupKind      = $definition.GroupKind
                    MembershipType = $definition.MembershipType
                    MembershipRule = $definition.MembershipRule
                    RoleAssignable = [bool]::Parse($definition.IsAssignableToRole)
                    Tier           = $definition.Tier
                    Purpose        = $definition.Purpose
                }
            })
    }
}
