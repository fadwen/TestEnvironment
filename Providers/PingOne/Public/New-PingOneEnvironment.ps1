function New-PingOneEnvironment {
    <#
    .SYNOPSIS
        Seeds a PingOne environment with populations, people, groups, resources and applications

    .DESCRIPTION
        Reached through New-TestEnvironment once a PingOne connection is active. Runs every step
        in the only order that works, and keeps going when a step fails so the summary can say
        what did and did not happen rather than stopping at the first error.

        The order is dictated by what references what:

        1. Attributes     - the custom schema attributes, including the ownership marker every
                            seeded user is written with. Nothing can be tagged before it exists.
        2. Populations    - the containers teardown asks. A user cannot be created without one.
        3. Groups         - including the chain's nesting and the dynamic filters, which name a
                            population by id and so need it to exist.
        4. Users          - created in their populations, tagged, and then put into their
                            groups, which is why groups come first.
        5. Resources      - the custom APIs and their scopes.
        6. Applications   - restricted to groups and granted resource scopes, so both of those
                            have to exist already.

        What is deliberately never done, and has no parameter:

        - No seeded population is made the environment's default. The default decides where
          every user created without a population lands, including users nothing to do with
          this module, so changing it changes how the environment behaves.
        - No platform application or built-in resource is created, edited or deleted. They are
          matched by type rather than name, so renaming one in the console cannot change that.
        - No public client is created without PKCE. Seeding an unsafe one would be seeding a
          live weakness rather than inert data.

        The whole run is idempotent: every step reuses what already exists, so a run that
        stopped halfway can simply be run again.

    .PARAMETER Skip
        Steps to leave out.

    .PARAMETER Tier
        Seed only the Core users (the hand-designed edge cases) or only the Bulk users (the
        generated volume). Both by default. Every other object type is
        hand-designed and seeded whole.

    .PARAMETER ShowProgress
        Report progress per user.

    .PARAMETER PassThru
        Return the results object.

    .OUTPUTS
        PSCustomObject describing every step, when -PassThru is used.

    .EXAMPLE
        PS> New-TestEnvironment -WhatIf

        DESCRIPTION: Shows every object the seed would create, creating none
        OUTPUT: A What if: line per object
        USE CASE: Checking what a seed will do before running it against an environment you care about

    .EXAMPLE
        PS> New-TestEnvironment -Tier Core -PassThru

        DESCRIPTION: Seeds every object type with only the designed people
        OUTPUT: The results object
        USE CASE: The fast loop, when the test is behaviour rather than scale

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        Connect-PingOneEnvironment
        Get-PingOneEnvironmentReport
        Remove-PingOneEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The step summary is written for the person watching the seed run; the result object carries the same data for scripts.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the step functions, which each call ShouldProcess per object.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Attributes', 'Populations', 'Groups', 'Users', 'Resources', 'Applications')]
        [string[]]$Skip = @(),

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting New-PingOneEnvironment - CorrelationId: $correlationId"

    $connection = Get-PingOneConnection
    $startTime = Get-Date

    Write-TestMessage -Message ("PingOne Test Environment Creation ({0}, {1})" -f
        $connection.EnvironmentName, $connection.EnvironmentId) -Type Header

    # The user step is the only one that takes arguments from this command. They are built here,
    # rather than read from inside the step's scriptblock, so the parameters are visibly used.
    $userArguments = @{ PassThru = $true; ShowProgress = $ShowProgress }
    if ($Tier) { $userArguments['Tier'] = $Tier }

    # Each step is a name and the call that performs it. Held as data so the order is written
    # once and the loop below cannot drift from it.
    $plan = @(
        @{ Name = 'Attributes'; Label = 'Creating custom user attributes'; Run = { New-PingOneProfileAttribute -PassThru } }
        @{ Name = 'Populations'; Label = 'Creating populations'; Run = { New-PingOnePopulation -PassThru } }
        @{ Name = 'Groups'; Label = 'Creating groups and nesting them'; Run = { New-PingOneGroup -PassThru } }
        @{ Name = 'Users'; Label = 'Creating users and their memberships'; Run = { New-PingOneUser @userArguments } }
        @{ Name = 'Resources'; Label = 'Creating resources and scopes'; Run = { New-PingOneResource -PassThru } }
        @{ Name = 'Applications'; Label = 'Creating applications and granting scopes'; Run = { New-PingOneApplication -PassThru } }
    )

    $steps = [System.Collections.Generic.List[object]]::new()
    $number = 0

    foreach ($step in $plan) {
        $number++
        if ($Skip -contains $step.Name) {
            Write-Host ("Step {0}: Skipping {1}" -f $number, $step.Name.ToLowerInvariant())
            $steps.Add([PSCustomObject]@{ Name = $step.Name; Attempted = $false; Success = $false; Result = $null; Errors = @() })
            continue
        }

        Write-Host ("Step {0}: {1}" -f $number, $step.Label)

        try {
            $result = & $step.Run
            $stepErrors = @()
            if ($result -and $result.Errors) { $stepErrors = @($result.Errors) }
            $steps.Add([PSCustomObject]@{
                    Name      = $step.Name
                    Attempted = $true
                    Success   = ($stepErrors.Count -eq 0)
                    Result    = $result
                    Errors    = $stepErrors
                })
        }
        catch {
            # A step that throws is recorded rather than allowed to end the run, so the steps
            # after it that do not depend on it still happen and the summary says what stopped.
            Write-Warning "Step $($step.Name) failed: $($_.Exception.Message)"
            $steps.Add([PSCustomObject]@{
                    Name      = $step.Name
                    Attempted = $true
                    Success   = $false
                    Result    = $null
                    Errors    = @("Step $($step.Name) failed: $($_.Exception.Message)")
                })
        }
    }

    $endTime = Get-Date
    $attempted = @($steps | Where-Object Attempted)
    $failed = @($attempted | Where-Object { -not $_.Success })

    Write-TestMessage -Message 'Environment Creation Summary' -Type Header
    Write-Host ("Operations Completed: {0}/{1}" -f ($attempted.Count - $failed.Count), $attempted.Count)
    Write-Host ("Duration: {0:hh\:mm\:ss}" -f ($endTime - $startTime))
    foreach ($step in $failed) {
        foreach ($message in $step.Errors) { Write-Host ("  ! {0}" -f $message) }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            CorrelationId   = $correlationId
            EnvironmentId   = $connection.EnvironmentId
            EnvironmentName = $connection.EnvironmentName
            Prefix          = $connection.Prefix
            StartTime       = $startTime
            EndTime         = $endTime
            Duration        = $endTime - $startTime
            Steps           = $steps.ToArray()
            Summary         = [PSCustomObject]@{
                TotalSteps      = $steps.Count
                AttemptedSteps  = $attempted.Count
                SuccessfulSteps = $attempted.Count - $failed.Count
                FailedSteps     = $failed.Count
            }
        }
    }
}
