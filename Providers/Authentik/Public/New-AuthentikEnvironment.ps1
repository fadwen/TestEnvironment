function New-AuthentikEnvironment {
    <#
    .SYNOPSIS
        Seeds the complete Authentik test environment in dependency order

    .DESCRIPTION
        Runs the eleven component functions in the only order that works: groups before the
        users that join them and the roles assigned to them, applications before the scope
        mappings, entitlements and policies that attach to them, notification rules before
        the bindings that make them fire, and tokens and invitations last because nothing
        depends on them. Each step is attempted, recorded and followed by the next, so one
        failing step does not abandon the rest.

        A step that returns normally has not necessarily worked. Every component collects what
        it could not do into an Errors property rather than throwing on the first bad row, so
        the orchestrator reads that property and counts a step with errors as failed. Counting
        only thrown exceptions is how an earlier provider reported success over a screen of
        failures.

        There is no ShouldProcess gate at this level. Each step runs its own, and
        $WhatIfPreference reaches into them, which is what makes -WhatIf list every group,
        user and application by name rather than saying only that a step would run.

    .PARAMETER Skip
        Steps to leave out: Groups, Users, Roles, Applications, ScopeMappings, Entitlements,
        Policies, NotificationRules, Bindings, Tokens, Invitations.

    .PARAMETER AccountPassword
        A password to set on every seeded user. Without it they cannot sign in.

    .PARAMETER ShowProgress
        Show a progress bar through the groups and users steps, which are the long ones at
        three hundred users, and report each step's counts as it completes.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with CorrelationId, BaseUrl, Prefix, StartTime, EndTime, Duration,
        Operations and Summary.

    .EXAMPLE
        PS> New-AuthentikEnvironment

        DESCRIPTION: Seeds everything
        OUTPUT: A summary line per step and a closing verdict
        USE CASE: Called by New-TestEnvironment when Authentik is the active provider

    .EXAMPLE
        PS> New-AuthentikEnvironment -Skip Policies, NotificationRules -PassThru

        DESCRIPTION: Seeds the directory objects only
        OUTPUT: The result object with three attempted steps
        USE CASE: An instance where policies would govern real sign-ins

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
        [ValidateSet('Groups', 'Users', 'Roles', 'Applications', 'ScopeMappings', 'Entitlements',
            'Policies', 'NotificationRules', 'Bindings', 'Tokens', 'Invitations')]
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
        Write-Verbose "Starting New-AuthentikEnvironment - CorrelationId: $correlationId"

        $connection = Get-AuthentikConnection

        if (-not (Test-AuthentikPrerequisite -CheckDataFiles)) {
            throw 'Prerequisites not met for Authentik test environment creation'
        }
    }

    process {
        Write-TestMessage -Message "Authentik Test Environment Creation ($($connection.BaseUrl))" -Type Header

        $results = [PSCustomObject]@{
            CorrelationId = $correlationId
            BaseUrl       = $connection.BaseUrl
            Prefix        = $connection.Prefix
            StartTime     = Get-Date
            EndTime       = $null
            Duration      = $null
            Operations    = [ordered]@{
                Groups            = @{ Attempted = $false; Success = $false; Results = $null }
                Users             = @{ Attempted = $false; Success = $false; Results = $null }
                Roles             = @{ Attempted = $false; Success = $false; Results = $null }
                Applications      = @{ Attempted = $false; Success = $false; Results = $null }
                ScopeMappings     = @{ Attempted = $false; Success = $false; Results = $null }
                Entitlements      = @{ Attempted = $false; Success = $false; Results = $null }
                Policies          = @{ Attempted = $false; Success = $false; Results = $null }
                NotificationRules = @{ Attempted = $false; Success = $false; Results = $null }
                Bindings          = @{ Attempted = $false; Success = $false; Results = $null }
                Tokens            = @{ Attempted = $false; Success = $false; Results = $null }
                Invitations       = @{ Attempted = $false; Success = $false; Results = $null }
            }
            Summary       = [ordered]@{
                TotalOperations      = 0
                SuccessfulOperations = 0
                FailedOperations     = 0
            }
        }

        $groupArgs = @{ PassThru = $true; Confirm = $false; ShowProgress = $ShowProgress }
        $userArgs = @{ PassThru = $true; Confirm = $false; ShowProgress = $ShowProgress }
        if ($AccountPassword) { $userArgs['AccountPassword'] = $AccountPassword }

        $steps = @(
            @{
                Key    = 'Groups'
                Title  = 'Step 1: Creating groups'
                Run    = { New-AuthentikGroup @groupArgs }
                Report = { param($r) "$($r.CreatedGroups) created, $($r.UpdatedGroups) updated" }
            }
            @{
                Key    = 'Users'
                Title  = 'Step 2: Creating users'
                Run    = { New-AuthentikUser @userArgs }
                Report = { param($r) "$($r.CreatedUsers) created, $($r.UpdatedUsers) updated" }
            }
            @{
                Key    = 'Roles'
                Title  = 'Step 3: Creating roles and assigning them to groups'
                Run    = { New-AuthentikRole -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRoles) created, $($r.GroupsAssigned) group assignments" }
            }
            @{
                Key    = 'Applications'
                Title  = 'Step 4: Creating applications and providers'
                Run    = { New-AuthentikApplication -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedApplications) created, $($r.ProvidersCreated) providers" }
            }
            @{
                Key    = 'ScopeMappings'
                Title  = 'Step 5: Creating scope mappings and attaching them to providers'
                Run    = { New-AuthentikScopeMapping -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedMappings) created, $($r.ProvidersUpdated) providers updated" }
            }
            @{
                Key    = 'Entitlements'
                Title  = 'Step 6: Creating application entitlements'
                Run    = { New-AuthentikEntitlement -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedEntitlements) created" }
            }
            @{
                Key    = 'Policies'
                Title  = 'Step 7: Creating policies and their application bindings'
                Run    = { New-AuthentikPolicy -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedPolicies) created, $($r.BindingsCreated) bindings" }
            }
            @{
                Key    = 'NotificationRules'
                Title  = 'Step 8: Creating notification rules'
                Run    = { New-AuthentikNotificationRule -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedRules) created, $($r.TransportsCreated) transports" }
            }
            @{
                Key    = 'Bindings'
                Title  = 'Step 9: Creating group, user and policy bindings'
                Run    = { New-AuthentikBinding -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedBindings) created, $($r.ExistingBindings) existing" }
            }
            @{
                Key    = 'Tokens'
                Title  = 'Step 10: Creating user tokens'
                Run    = { New-AuthentikToken -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedTokens) created" }
            }
            @{
                Key    = 'Invitations'
                Title  = 'Step 11: Creating invitations'
                Run    = { New-AuthentikInvitation -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedInvitations) created" }
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
        Write-Verbose "Completed New-AuthentikEnvironment - CorrelationId: $correlationId"
    }
}
