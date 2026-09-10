function New-EntraConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Creates the seeded Conditional Access policies, always in report-only state

    .DESCRIPTION
        Creates eight Conditional Access policies covering the control shapes that outcome
        evaluation has to get right: a plain MFA grant, a device-compliance grant that is
        unsatisfiable for anyone on a non-compliant device, a legacy-authentication block, an
        inverted location condition, a risk-conditioned policy, a session-controls-only
        policy with no grant control at all, an authentication strength, and an AND of two
        controls where satisfying one is not enough.

        Every one of them is created in enabledForReportingButNotEnforced, and there is no
        parameter to change that. This is the single most consequential decision in the
        module and it is deliberately not configurable.

        A Conditional Access policy is the one object here that can deny a real person access
        to a real account. These are seeded into a tenant that is in real use, alongside
        policies that genuinely protect it. A report-only policy is fully evaluated and fully
        logged - it appears in sign-in logs, it can be read back, and What If will return it -
        but it never denies anything. That gives the whole value of having the policies for
        none of the risk. Anything that wants one enforced can enable it deliberately in the
        portal, having read it, which is a decision a human should make once rather than a
        switch a script flips by default.

        Scoping is to seeded groups only, never to all users. A policy scoped to all users in
        a live tenant is how a lab object stops being a lab object, and report-only or not,
        it would appear in every sign-in log entry for every real person in the directory.

        Authentication strengths are looked up by display name at run time rather than by the
        well-known GUID. The built-in strengths do have fixed ids, but resolving them by name
        means the policy still builds against a tenant where somebody has replaced the
        built-in with a custom strength of the same name - which is exactly the case a
        baseline is supposed to catch.

    .PARAMETER PolicyKey
        Creates only the named policies, by their Key column. Defaults to all of them.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created policies

    .OUTPUTS
        EntraConditionalAccessPolicy[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraConditionalAccessPolicy

        DESCRIPTION: Creates all eight policies, every one report-only
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment, and the input CaOutcome evaluates against

    .EXAMPLE
        PS> New-EntraConditionalAccessPolicy -PolicyKey ca-compliant-device -PassThru

        DESCRIPTION: Creates just the policy that is unsatisfiable on a non-compliant device
        OUTPUT: The policy object
        USE CASE: Reproducing the promotion that locks out an unmanaged device

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraConditionalAccessPolicy')]
    param(
        [Parameter()]
        [string[]]$PolicyKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraConditionalAccessPolicies')
    if ($PolicyKey) {
        $definitions = @($definitions | Where-Object { $PolicyKey -contains $_.Key })
        $missing = @($PolicyKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for policy key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    $cache = @{}

    # Named locations are resolved once. They are referenced by key in the CSV and a policy
    # that silently loses its location condition is a policy that quietly means something
    # else, so a missing one is a warning that costs the condition rather than a silent drop.
    $locationDefinitions = @(Get-EntraSeedData -Name 'EntraNamedLocations')

    # Only the locations some policy actually names need to resolve. Requiring all of them
    # would make an unreferenced location's absence block policies that do not use it.
    $referencedLocationKeys = @(
        foreach ($definition in $definitions) {
            ($definition.IncludeLocations -split ';' | Where-Object { $_ })
            ($definition.ExcludeLocations -split ';' | Where-Object { $_ })
        }
    ) | ForEach-Object { $_.Trim() } | Sort-Object -Unique

    $locationsByKey = @{}
    $buildLocationMap = {
        $locationsByKey = @{}
        foreach ($locationDefinition in (@(Get-EntraSeededObject -Type NamedLocations -Connection $connection))) {
            foreach ($candidate in $locationDefinitions) {
                if ($locationDefinition.displayName -eq ('{0}{1}' -f $marker.Prefix, $candidate.DisplayName)) {
                    $locationsByKey[$candidate.Key] = $locationDefinition.id
                }
            }
        }
        return $locationsByKey
    }

    $locationsByKey = & $buildLocationMap

    # Applications are addressed by appId, not by directory object id - Conditional Access names
    # the client identifier, and passing the object id yields a policy that silently matches
    # nothing at all. Built once here for the same reason the location map is.
    $applicationDefinitions = @(Get-EntraSeedData -Name 'EntraApplications')
    $applicationsByKey = @{}
    foreach ($seededApp in (@(Get-EntraSeededObject -Type Applications -Connection $connection))) {
        foreach ($candidate in $applicationDefinitions) {
            if ($seededApp.displayName -eq ('{0}{1}' -f $marker.Prefix, $candidate.DisplayName)) {
                $applicationsByKey[$candidate.Key] = $seededApp.appId
            }
        }
    }

    # The named locations step runs immediately before this one, and Graph does not list a
    # location the instant it is created. Without this retry a policy silently loses its
    # location condition on a full seed and keeps it on a re-run, which is the most
    # confusing kind of intermittent.
    $missingLocationKeys = @($referencedLocationKeys | Where-Object { -not $locationsByKey.ContainsKey($_) })
    if ($missingLocationKeys -and -not $WhatIfPreference) {
        Write-Verbose ("Named location(s) $($missingLocationKeys -join ', ') are not listed yet; " +
            'waiting for replication before giving up on them.')
        foreach ($delay in 5, 10, 15) {
            Start-Sleep -Seconds $delay
            $locationsByKey = & $buildLocationMap
            $missingLocationKeys = @($referencedLocationKeys | Where-Object { -not $locationsByKey.ContainsKey($_) })
            if (-not $missingLocationKeys) { break }
        }
    }

    $strengthsByName = @{}
    try {
        foreach ($strength in (Invoke-EntraRequest -Method GET -Path '/identity/conditionalAccess/authenticationStrength/policies' -Connection $connection).value) {
            $strengthsByName[$strength.displayName] = $strength.id
        }
    }
    catch {
        Write-Warning "Could not read the tenant's authentication strengths: $($_.Exception.Message)"
    }

    # Entra places no uniqueness constraint on a policy's displayName, so without this a re-run
    # creates a second copy of every policy - and a duplicated Conditional Access policy is a
    # worse thing to leave behind than a duplicated group.
    $existingByName = @{}
    foreach ($policy in (Get-EntraSeededObject -Type ConditionalAccessPolicies -Connection $connection)) {
        $existingByName[$policy.displayName] = $policy
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName

        Write-TestProgress -Activity 'Seeding Conditional Access policies' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        if ($existingByName.ContainsKey($displayName)) {
            Write-Verbose "Conditional Access policy '$displayName' already exists; reusing it"
            $created.Add([PSCustomObject]@{
                    PSTypeName    = 'EntraConditionalAccessPolicy'
                    Key           = $definition.Key
                    Id            = $existingByName[$displayName].id
                    DisplayName   = $displayName
                    State         = $existingByName[$displayName].state
                    IncludeGroups = @($definition.IncludeGroups -split ';' | Where-Object { $_ })
                    GrantControls = @($definition.GrantControls -split ';' | Where-Object { $_ })
                    Operator      = $definition.GrantOperator
                    Purpose       = $definition.Purpose
                })
            continue
        }

        $includeGroupIds = @(foreach ($key in ($definition.IncludeGroups -split ';' | Where-Object { $_ })) {
                $id = Resolve-EntraSeededId -Key $key.Trim() -Kind Group -Cache $cache -Connection $connection
                if ($id) { $id } else { Write-Warning "Policy '$($definition.Key)' includes group '$($key.Trim())', which does not exist." }
            })

        if (-not $includeGroupIds) {
            # An unscoped Conditional Access policy applies to everyone in the tenant. Even
            # report-only, that would put a lab object into every real person's sign-in
            # evaluation, so a policy that resolves no groups is refused rather than created.
            Write-Error ("Policy '$($definition.Key)' resolved no groups to scope to, and an unscoped " +
                "Conditional Access policy applies tenant-wide. Refusing to create it.") -ErrorAction Continue
            continue
        }

        $excludeGroupIds = @(foreach ($key in ($definition.ExcludeGroups -split ';' | Where-Object { $_ })) {
                $id = Resolve-EntraSeededId -Key $key.Trim() -Kind Group -Cache $cache -Connection $connection
                if ($id) { $id } else { Write-Warning "Policy '$($definition.Key)' excludes group '$($key.Trim())', which does not exist." }
            })

        # Named users rather than a group, because that is how a break-glass exclusion is written
        # in practice and it is the shape most likely to be got wrong by a script reading policy.
        $excludeUserIds = @(foreach ($key in ($definition.ExcludeUsers -split ';' | Where-Object { $_ })) {
                $id = Resolve-EntraSeededId -Key $key.Trim() -Kind User -Cache $cache -Connection $connection
                if ($id) { $id } else { Write-Warning "Policy '$($definition.Key)' excludes user '$($key.Trim())', which does not exist." }
            })

        # 'All' passes through; anything else is a seed application key resolved to its appId.
        # Every policy used to target All, which left the eight seeded applications referenced by
        # nothing and made "which policies affect this app" unanswerable in the lab.
        $includeApplicationIds = @(foreach ($key in ($definition.IncludeApplications -split ';' | Where-Object { $_ })) {
                $trimmed = $key.Trim()
                if ($trimmed -eq 'All') { 'All' }
                elseif ($applicationsByKey.ContainsKey($trimmed)) { $applicationsByKey[$trimmed] }
                else {
                    Write-Warning "Policy '$($definition.Key)' targets application '$trimmed', which does not exist. Skipping the policy rather than widening it to All."
                    $null
                }
            })

        if (@($includeApplicationIds | Where-Object { $_ }).Count -eq 0) {
            # Falling back to All here would turn a policy meant for one application into one
            # that touches every application in the tenant. Refused, exactly as an unscoped
            # policy is refused above.
            Write-Error ("Policy '$($definition.Key)' resolved no applications to target. Refusing to create it, " +
                'because defaulting to All would widen it to the whole tenant.') -ErrorAction Continue
            continue
        }

        $conditions = @{
            users = @{
                includeGroups = $includeGroupIds
                excludeGroups = $excludeGroupIds
                excludeUsers  = $excludeUserIds
            }
            applications = @{
                includeApplications = @($includeApplicationIds | Where-Object { $_ })
            }
            clientAppTypes = @($definition.ClientAppTypes -split ';' | Where-Object { $_ })
        }

        $platforms = @($definition.IncludePlatforms -split ';' | Where-Object { $_ })
        if ($platforms) {
            $conditions.platforms = @{ includePlatforms = $platforms; excludePlatforms = @() }
        }

        $includeLocationIds = @(foreach ($key in ($definition.IncludeLocations -split ';' | Where-Object { $_ })) {
                if ($locationsByKey.ContainsKey($key.Trim())) { $locationsByKey[$key.Trim()] }
                else { Write-Warning "Policy '$($definition.Key)' includes location '$($key.Trim())', which does not exist. The condition is weaker than intended." }
            })
        $excludeLocationIds = @(foreach ($key in ($definition.ExcludeLocations -split ';' | Where-Object { $_ })) {
                if ($locationsByKey.ContainsKey($key.Trim())) { $locationsByKey[$key.Trim()] }
                else { Write-Warning "Policy '$($definition.Key)' excludes location '$($key.Trim())', which does not exist. The condition is weaker than intended." }
            })

        if ($includeLocationIds -or $excludeLocationIds) {
            # 'All' rather than the include list when only exclusions are named: the inverted
            # form - everywhere except these - is the one the CSV describes, and writing the
            # exclusions without it would produce a policy that applies nowhere.
            #
            # The outer @() is load-bearing and cannot be dropped. Assigning the result of an
            # if expression unrolls a single-element array to a scalar, so this produced
            # "includeLocations":"All" rather than ["All"]. Graph rejects that with error 1007,
            # "does not match the schema of ConditionalAccessPolicy type", naming no field -
            # which reads exactly like a transient failure and is not one.
            $conditions.locations = @{
                includeLocations = @(if ($includeLocationIds) { $includeLocationIds } else { 'All' })
                excludeLocations = @($excludeLocationIds)
            }
        }

        $riskLevels = @($definition.SignInRiskLevels -split ';' | Where-Object { $_ })
        if ($riskLevels) { $conditions.signInRiskLevels = $riskLevels }

        # Sign-in risk and user risk are different conditions and are routinely confused by
        # scripts that read policy, which is reason enough for the data to carry both.
        $userRiskLevels = @($definition.UserRiskLevels -split ';' | Where-Object { $_ })
        if ($userRiskLevels) { $conditions.userRiskLevels = $userRiskLevels }

        # Report-only unless the row asks for disabled, and never anything else. The rule this
        # protects is "this module cannot create an ENFORCING policy" - report-only logs without
        # acting, disabled does not even log, and both are safe in a tenant somebody uses. A
        # disabled policy is there because real tenants have them and an inventory script must
        # not count one as active. Anything other than these two values is refused rather than
        # trusted, so a typo in the CSV cannot produce an enabled policy.
        $requestedState = if ($definition.PSObject.Properties.Name -contains 'State' -and $definition.State) {
            $definition.State.Trim()
        }
        else { 'enabledForReportingButNotEnforced' }

        if ($requestedState -notin @('enabledForReportingButNotEnforced', 'disabled')) {
            Write-Error ("Policy '$($definition.Key)' asks for state '$requestedState'. Only " +
                "'enabledForReportingButNotEnforced' and 'disabled' are permitted, because this module " +
                'must never create an enforcing Conditional Access policy. Refusing to create it.') -ErrorAction Continue
            continue
        }

        $body = @{
            displayName = $displayName
            state       = $requestedState
            conditions  = $conditions
        }

        $controls = @($definition.GrantControls -split ';' | Where-Object { $_ })
        if ($controls) {
            $builtIn = @($controls | Where-Object { $_ -ne 'authenticationStrength' })
            $grant = @{
                operator        = $definition.GrantOperator
                builtInControls = $builtIn
            }

            if ($controls -contains 'authenticationStrength') {
                # The seeded custom strength first, then the built-in of the same intent. The
                # custom one is preferred because it is editable, which is the whole point:
                # widening it weakens every policy referencing it with no policy changing, and
                # a baseline can only catch that if the policy points at an object this module
                # controls. The built-in is the fallback so the policy is still meaningful when
                # the strengths step was skipped.
                $strengthName = @(
                    '{0}Phishing Resistant Lab' -f $marker.Prefix
                    'Phishing-resistant MFA'
                ) | Where-Object { $strengthsByName.ContainsKey($_) } | Select-Object -First 1

                if ($strengthName) {
                    $grant.authenticationStrength = @{ id = $strengthsByName[$strengthName] }
                    Write-Verbose "Policy '$($definition.Key)' uses authentication strength '$strengthName'"
                }
                else {
                    Write-Warning ("Policy '$($definition.Key)' wants an authentication strength, and neither the " +
                        "seeded one nor the built-in exists. Falling back to a plain MFA grant.")
                    $grant.builtInControls = @($builtIn + 'mfa')
                }
            }

            $body.grantControls = $grant
        }

        $sessionSpecs = @($definition.SessionControls -split ';' | Where-Object { $_ })
        if ($sessionSpecs) {
            $session = @{}
            foreach ($spec in $sessionSpecs) {
                $parts = $spec -split ':'
                switch ($parts[0]) {
                    'signInFrequency' {
                        $session.signInFrequency = @{
                            isEnabled = $true
                            type      = $parts[2]
                            value     = [int]$parts[1]
                        }
                    }
                    'persistentBrowser' {
                        $session.persistentBrowser = @{ isEnabled = $true; mode = $parts[1] }
                    }
                    default { Write-Warning "Policy '$($definition.Key)' names unknown session control '$($parts[0])'." }
                }
            }
            if ($session.Count -gt 0) { $body.sessionControls = $session }
        }

        # Conditional Access rejects a body it dislikes with a single generic schema error
        # that names no field, so the body is worth having in a transcript when that happens.
        Write-Verbose "Policy '$($definition.Key)' body: $($body | ConvertTo-Json -Depth 20 -Compress)"

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create report-only Conditional Access policy')) { continue }

        try {
            # Deliberately not retried. Conditional Access reports every body it dislikes as
            # error 1007 - "object is null or does not match the schema" - naming no field,
            # which is easy to mistake for a transient. It is not: the one time this fired in
            # development the body was genuinely wrong, and retrying only delayed the message
            # by half a minute. The verbose body dump above is what actually diagnoses it.
            $policy = Invoke-EntraRequest -Method POST -Path '/identity/conditionalAccess/policies' -Body $body
        }
        catch {
            Write-Error "Failed to create Conditional Access policy '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName    = 'EntraConditionalAccessPolicy'
                Key           = $definition.Key
                Id            = $policy.id
                DisplayName   = $displayName
                State         = $policy.state
                IncludeGroups = @($definition.IncludeGroups -split ';' | Where-Object { $_ })
                GrantControls = $controls
                Operator      = $definition.GrantOperator
                Purpose       = $definition.Purpose
            })

        Write-Verbose "Created report-only policy '$displayName' ($($policy.id))"
    }

    Write-TestProgress -Activity 'Seeding Conditional Access policies' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
