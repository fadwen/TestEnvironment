function New-FreeIPAEnvironment {
    <#
    .SYNOPSIS
        Seeds the complete FreeIPA test environment in dependency order

    .DESCRIPTION
        Runs the component functions in the only order that works: groups before the users
        that join them, host groups before the hosts that join them, and then the access
        layers that name all four - netgroups, HBAC rules, sudo rules, roles, password
        policies and services - each of which needs the directory to exist, and last the
        identity detail: ID views over users and hosts, tokens on users, automember rules
        rebuilt against the seeded entries, the automount location, SELinux maps over the
        HBAC rules, and certificate mapping. Each step is attempted, recorded and followed by
        the next, so one failing step does not abandon the rest.

        A step that returns normally has not necessarily worked. Every component collects what
        it could not do into an Errors property rather than throwing on the first bad row, so
        the orchestrator reads that property and counts a step with errors as failed. Counting
        only thrown exceptions is how an earlier provider reported success over a screen of
        failures.

        There is no ShouldProcess gate at this level. Each step runs its own, and
        $WhatIfPreference reaches into them, which is what makes -WhatIf list every group,
        user and host by name rather than saying only that a step would run.

    .PARAMETER Skip
        Steps to leave out: Groups, Users, Hostgroups, Hosts, Netgroups, HbacRules, SudoRules,
        Roles, PasswordPolicies, Services, IdViews, OtpTokens, AutomemberRules, Automount,
        SelinuxUserMaps, CertMapRules, CaAcls, Certificates.

    .PARAMETER AccountPassword
        A password to set on the seeded users whose row asks for one. Without it nobody can
        log in.

    .PARAMETER ShowProgress
        Show a progress bar through the long steps, and report each step's counts as it
        completes.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with CorrelationId, BaseUrl, Prefix, StartTime, EndTime, Duration,
        Operations and Summary.

    .EXAMPLE
        PS> New-FreeIPAEnvironment

        DESCRIPTION: Seeds everything
        OUTPUT: A summary line per step and a closing verdict
        USE CASE: Called by New-TestEnvironment when FreeIPA is the active provider

    .EXAMPLE
        PS> New-FreeIPAEnvironment -Skip Hosts, Hostgroups -PassThru

        DESCRIPTION: Seeds the people and groups only
        OUTPUT: The result object with two attempted steps
        USE CASE: A realm where the host inventory is not wanted

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The step summary is written for the person watching the seed run; the result object carries the same data for scripts.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the step functions, which each call ShouldProcess per object.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Groups', 'Users', 'Hostgroups', 'Hosts', 'Netgroups', 'HbacRules', 'SudoRules', 'Roles',
            'PasswordPolicies', 'Services', 'IdViews', 'OtpTokens', 'AutomemberRules', 'Automount', 'SelinuxUserMaps',
            'CertMapRules', 'CaAcls', 'Certificates')]
        [string[]]$Skip = @(),

        [Parameter()]
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $correlationId = [Guid]::NewGuid()
        Write-Verbose "Starting New-FreeIPAEnvironment - CorrelationId: $correlationId"

        $connection = Get-FreeIPAConnection

        if (-not (Test-FreeIPAPrerequisite -CheckDataFiles)) {
            throw 'Prerequisites not met for FreeIPA test environment creation'
        }
    }

    process {
        Write-TestMessage -Message "FreeIPA Test Environment Creation ($($connection.BaseUrl))" -Type Header

        $results = [PSCustomObject]@{
            CorrelationId = $correlationId
            BaseUrl       = $connection.BaseUrl
            Prefix        = $connection.Prefix
            StartTime     = Get-Date
            EndTime       = $null
            Duration      = $null
            Operations    = [ordered]@{
                Groups     = @{ Attempted = $false; Success = $false; Results = $null }
                Users      = @{ Attempted = $false; Success = $false; Results = $null }
                Hostgroups       = @{ Attempted = $false; Success = $false; Results = $null }
                Hosts            = @{ Attempted = $false; Success = $false; Results = $null }
                Netgroups        = @{ Attempted = $false; Success = $false; Results = $null }
                HbacRules        = @{ Attempted = $false; Success = $false; Results = $null }
                SudoRules        = @{ Attempted = $false; Success = $false; Results = $null }
                Roles            = @{ Attempted = $false; Success = $false; Results = $null }
                PasswordPolicies = @{ Attempted = $false; Success = $false; Results = $null }
                Services         = @{ Attempted = $false; Success = $false; Results = $null }
                IdViews          = @{ Attempted = $false; Success = $false; Results = $null }
                OtpTokens        = @{ Attempted = $false; Success = $false; Results = $null }
                AutomemberRules  = @{ Attempted = $false; Success = $false; Results = $null }
                Automount        = @{ Attempted = $false; Success = $false; Results = $null }
                SelinuxUserMaps  = @{ Attempted = $false; Success = $false; Results = $null }
                CertMapRules     = @{ Attempted = $false; Success = $false; Results = $null }
                CaAcls           = @{ Attempted = $false; Success = $false; Results = $null }
                Certificates     = @{ Attempted = $false; Success = $false; Results = $null }
            }
            Summary       = [ordered]@{
                TotalOperations      = 0
                SuccessfulOperations = 0
                FailedOperations     = 0
            }
        }

        $stepArgs = @{ PassThru = $true; Confirm = $false; ShowProgress = $ShowProgress }
        $userArgs = @{ PassThru = $true; Confirm = $false; ShowProgress = $ShowProgress }
        if ($AccountPassword) { $userArgs['AccountPassword'] = $AccountPassword }

        $steps = @(
            @{
                Key    = 'Groups'
                Title  = 'Step 1: Creating groups'
                Run    = { New-FreeIPAGroup @stepArgs }
                Report = { param($r) "$($r.CreatedGroups) created, $($r.UpdatedGroups) updated, $($r.NestingsApplied) nestings" }
            }
            @{
                Key    = 'Users'
                Title  = 'Step 2: Creating users'
                Run    = { New-FreeIPAUser @userArgs }
                Report = { param($r) "$($r.CreatedUsers) created, $($r.UpdatedUsers) updated, $($r.MembershipsApplied) memberships" }
            }
            @{
                Key    = 'Hostgroups'
                Title  = 'Step 3: Creating host groups'
                Run    = { New-FreeIPAHostgroup @stepArgs }
                Report = { param($r) "$($r.CreatedHostgroups) created, $($r.UpdatedHostgroups) updated, $($r.NestingsApplied) nestings" }
            }
            @{
                Key    = 'Hosts'
                Title  = 'Step 4: Creating hosts'
                Run    = { New-FreeIPAHost @stepArgs }
                Report = { param($r) "$($r.CreatedHosts) created, $($r.UpdatedHosts) updated, $($r.MembershipsApplied) memberships" }
            }
            @{
                Key    = 'Netgroups'
                Title  = 'Step 5: Creating netgroups'
                Run    = { New-FreeIPANetgroup -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedNetgroups) created, $($r.MembershipsApplied) memberships" }
            }
            @{
                Key    = 'HbacRules'
                Title  = 'Step 6: Creating HBAC services and rules'
                Run    = { New-FreeIPAHbacRule -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRules) rules, $($r.ServicesCreated) services, $($r.ServiceGroupsCreated) service groups" }
            }
            @{
                Key    = 'SudoRules'
                Title  = 'Step 7: Creating sudo commands and rules'
                Run    = { New-FreeIPASudoRule -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRules) rules, $($r.CommandsCreated) commands, $($r.CommandsReused) reused" }
            }
            @{
                Key    = 'Roles'
                Title  = 'Step 8: Creating permissions, privileges and roles'
                Run    = { New-FreeIPARole -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRoles) roles, $($r.PrivilegesCreated) privileges, $($r.PermissionsCreated) permissions" }
            }
            @{
                Key    = 'PasswordPolicies'
                Title  = 'Step 9: Creating password policies'
                Run    = { New-FreeIPAPasswordPolicy -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedPolicies) created, $($r.UpdatedPolicies) updated" }
            }
            @{
                Key    = 'Services'
                Title  = 'Step 10: Creating services and delegation rules'
                Run    = { New-FreeIPAService -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedServices) services, $($r.DelegationRulesCreated) rules, $($r.DelegationTargetsCreated) targets" }
            }
            @{
                Key    = 'IdViews'
                Title  = 'Step 11: Creating ID views and overrides'
                Run    = { New-FreeIPAIdView -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedViews) views, $($r.OverridesCreated) overrides, $($r.HostsApplied) applied" }
            }
            @{
                Key    = 'OtpTokens'
                Title  = 'Step 12: Creating OTP tokens'
                Run    = { New-FreeIPAOtpToken -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedTokens) created, $($r.UpdatedTokens) updated" }
            }
            @{
                Key    = 'AutomemberRules'
                Title  = 'Step 13: Creating automember rules and rebuilding the seeded entries'
                Run    = { New-FreeIPAAutomemberRule -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRules) rules, $($r.ConditionsApplied) conditions, $($r.EntriesRebuilt) entries rebuilt" }
            }
            @{
                Key    = 'Automount'
                Title  = 'Step 14: Creating the automount location, maps and keys'
                Run    = { New-FreeIPAAutomount -PassThru -Confirm:$false }
                Report = { param($r) "$($r.LocationsCreated) locations, $($r.MapsCreated) maps, $($r.KeysCreated) keys" }
            }
            @{
                Key    = 'SelinuxUserMaps'
                Title  = 'Step 15: Creating SELinux user maps'
                Run    = { New-FreeIPASelinuxUserMap -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedMaps) created, $($r.MembershipsApplied) memberships" }
            }
            @{
                Key    = 'CertMapRules'
                Title  = 'Step 16: Creating certificate mapping rules'
                Run    = { New-FreeIPACertMapRule -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRules) created, $($r.UpdatedRules) updated" }
            }
            @{
                Key    = 'CaAcls'
                Title  = 'Step 17: Creating CA ACLs'
                Run    = { New-FreeIPACaAcl -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedAcls) created, $($r.MembershipsApplied) memberships" }
            }
            @{
                Key    = 'Certificates'
                Title  = 'Step 18: Issuing certificates from the realm CA'
                Run    = { New-FreeIPACertificate -PassThru -Confirm:$false }
                Report = { param($r) "$($r.Issued) issued, $($r.Revoked) revoked, $($r.Existing) already there" }
            }
        )

        foreach ($step in $steps) {
            if ($step.Key -in $Skip) {
                Write-TestMessage -Message "$($step.Title) - skipped as requested" -Type Warning
                continue
            }

            Write-TestMessage -Message $step.Title -Type Info
            $results.Operations[$step.Key].Attempted = $true
            $results.Summary.TotalOperations++

            try {
                $stepResult = & $step.Run
                $results.Operations[$step.Key].Results = $stepResult

                $stepErrors = @()
                if ($stepResult -and ($stepResult.PSObject.Properties.Name -contains 'Errors')) {
                    $stepErrors = @($stepResult.Errors)
                }

                if ($stepErrors.Count -gt 0) {
                    $results.Operations[$step.Key].Success = $false
                    $results.Summary.FailedOperations++
                    foreach ($stepError in $stepErrors) {
                        Write-Error "$($step.Title): $stepError"
                    }
                }
                else {
                    $results.Operations[$step.Key].Success = $true
                    $results.Summary.SuccessfulOperations++
                }

                if ($ShowProgress -and $stepResult) {
                    Write-Verbose (& $step.Report $stepResult)
                }
            }
            catch {
                $results.Operations[$step.Key].Results = $_.Exception.Message
                $results.Summary.FailedOperations++
                Write-Error "$($step.Title) failed: $($_.Exception.Message)"
            }
        }

        $results.EndTime = Get-Date
        $results.Duration = $results.EndTime - $results.StartTime

        Write-TestMessage -Message 'Environment Creation Summary' -Type Header
        Write-Host ("Operations completed: $($results.Summary.SuccessfulOperations)/" +
            "$($results.Summary.TotalOperations)") -ForegroundColor Green
        Write-Host "Duration: $($results.Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

        if ($results.Summary.FailedOperations -gt 0) {
            Write-Warning "Failed operations: $($results.Summary.FailedOperations)"
            Write-Warning 'Inspect the results object with -PassThru for the detail.'
            Write-TestMessage -Message ('Test environment creation finished with ' +
                "$($results.Summary.FailedOperations) failed step(s).") -Type Error
        }
        else {
            Write-TestMessage -Message 'Test environment creation complete.' -Type Success
        }

        if ($PassThru) { return $results }
    }

    end {
        Write-Verbose "Completed New-FreeIPAEnvironment - CorrelationId: $correlationId"
    }
}
