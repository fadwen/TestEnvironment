function New-OneLoginEnvironment {
    <#
    .SYNOPSIS
        Seeds a OneLogin account with custom fields, roles, groups, apps, mappings and people

    .DESCRIPTION
        Reached through New-TestEnvironment once a OneLogin connection is active. Runs every step
        in the only order that works, and keeps going when a step fails so the summary can say
        what did and did not happen rather than stopping at the first error.

        The order is dictated by what references what:

        1.  Attributes        - the custom user fields, including the one every seeded user carries
                                the seed tag in. Nobody can be tagged before it exists.
        2.  Roles             - the roles the people being seeded will hold.
        3.  Groups            - the groups they will be placed in.
        4.  Policies          - user security policies, attached to seeded groups.
        5.  Apps              - granted to roles, so the roles come first.
        6.  AppRules          - entitlements on seeded apps by seeded role.
        7.  ApiAuthorizations - API authorization servers, with seeded apps as their clients.
        8.  Mappings          - each adds a role; before the people, so that an enabled mapping
                                acts as each person is created.
        9.  Hooks             - the disabled Smart Hook, gated on a seeded role.
        10. SelfRegistration  - the disabled, moderated sign-up profile.
        11. Users             - created in manager order with their lifecycle, group, manager,
                                directory identifiers and custom fields, locked where the data says,
                                then added to their roles.
        12. Mfa               - pre-verified factors, where the account already offers them.

        What is deliberately never done, and has no parameter:

        - No mapping is created without a condition requiring the seed tag, with match all. An
          enabled mapping can therefore act on seeded people and nobody else, which is what makes
          it safe to seed one into an account real people sign in to.
        - Nobody who is not seeded is ever added to a role or group, given a manager, or made a
          manager; and no app is granted to a role that holds anybody who is not. Every id the
          seed sends comes from a user it created or proved.
        - No role or group is created that no one being seeded will hold. OneLogin gives a role
          nothing but its name, so teardown proves one by its members; an empty one could never
          be claimed and would be left behind.
        - No seeded object can reach anything real, or be reached by it. A policy is attached to
          seeded groups only and is never the default; an app rule and a Smart Hook name seeded
          roles only; the hook is always disabled; the sign-up profile is always disabled,
          moderated and open to the lab domain alone; an API authorization serves seeded apps only;
          a person's directory identifiers are all under the seed prefix or the lab domain, so no
          directory connector or provisioning can link one to a real account. Risk rules are not
          seeded at all, because a rule acts on every sign-in in the account.
        - Nothing the account shipped with - the Default role, the default policy, the default
          brand - is created, edited or deleted, and no account-wide setting is changed: an MFA
          factor is enrolled only where the account already offers it.

        The whole run is idempotent: every step reuses what already exists and puts a reused
        person back as the data describes, so a run that stopped halfway can simply be run again.

    .PARAMETER Skip
        Steps to leave out.

    .PARAMETER Tier
        Seed only the Core people (the hand-designed edge cases) or only the Bulk people (the
        generated volume). Both by default. Roles, groups, apps and mappings follow the people:
        one that nobody in the chosen tiers would hold is not created.

    .PARAMETER ShowProgress
        Report progress per user.

    .PARAMETER SaveAppSecret
        Keep the client secret of each confidential app the seed creates, protected, so a sign-in
        can be tested against it with Get-OneLoginAppCredential. Off by default: nothing in the
        module needs the secrets. Teardown deletes each saved secret with its app.

    .PARAMETER UseSecretStore
        With -SaveAppSecret, keep the secrets in a SecretStore vault rather than DPAPI-protected in
        their records.

    .PARAMETER VaultPassword
        With -UseSecretStore, the vault's password when it is not the module default.

    .PARAMETER PassThru
        Return the results object.

    .OUTPUTS
        PSCustomObject describing every step, when -PassThru is used.

    .EXAMPLE
        PS> New-TestEnvironment -WhatIf

        DESCRIPTION: Shows every object the seed would create, creating none
        OUTPUT: A What if: line per object
        USE CASE: Checking what a seed will do before running it against an account you care about

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
        Connect-OneLoginEnvironment
        Get-OneLoginEnvironmentReport
        Remove-OneLoginEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The step summary is written for the person watching the seed run; the result object carries the same data for scripts.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the step functions, which each call ShouldProcess per object.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Attributes', 'Roles', 'Groups', 'Policies', 'Apps', 'AppRules', 'ApiAuthorizations', 'Mappings', 'Hooks', 'SelfRegistration', 'Users', 'Mfa')]
        [string[]]$Skip = @(),

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$SaveAppSecret,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting New-OneLoginEnvironment - CorrelationId: $correlationId"

    $connection = Get-OneLoginConnection
    $startTime = Get-Date

    Write-TestMessage -Message ('OneLogin Test Environment Creation ({0}.onelogin.com)' -f $connection.Subdomain) -Type Header

    # Built here, rather than read from inside each step's scriptblock, so the parameters are
    # visibly used. Every step but the fields takes the tier, because what exists follows who does.
    $tierArguments = @{ PassThru = $true }
    if ($Tier) { $tierArguments['Tier'] = $Tier }
    $userArguments = @{ PassThru = $true; ShowProgress = $ShowProgress }
    if ($Tier) { $userArguments['Tier'] = $Tier }
    $appArguments = @{} + $tierArguments
    if ($SaveAppSecret) {
        $appArguments['SaveAppSecret'] = $true
        $appArguments['UseSecretStore'] = $UseSecretStore
        if ($VaultPassword) { $appArguments['VaultPassword'] = $VaultPassword }
    }

    $plan = @(
        @{ Name = 'Attributes'; Label = 'Creating custom user fields'; Run = { New-OneLoginCustomAttribute -PassThru } }
        @{ Name = 'Roles'; Label = 'Creating roles'; Run = { New-OneLoginRole @tierArguments } }
        @{ Name = 'Groups'; Label = 'Creating groups'; Run = { New-OneLoginGroup @tierArguments } }
        @{ Name = 'Policies'; Label = 'Creating user security policies and attaching them to groups'; Run = { New-OneLoginPolicy @tierArguments } }
        @{ Name = 'Apps'; Label = 'Creating apps and granting them to roles'; Run = { New-OneLoginApp @appArguments } }
        @{ Name = 'AppRules'; Label = 'Creating app rules'; Run = { New-OneLoginAppRule @tierArguments } }
        @{ Name = 'ApiAuthorizations'; Label = 'Creating API authorization servers'; Run = { New-OneLoginApiAuthorization -PassThru } }
        @{ Name = 'Mappings'; Label = 'Creating mappings'; Run = { New-OneLoginMapping @tierArguments } }
        @{ Name = 'Hooks'; Label = 'Creating the disabled Smart Hook'; Run = { New-OneLoginSmartHook @tierArguments } }
        @{ Name = 'SelfRegistration'; Label = 'Creating the disabled self-registration profile'; Run = { New-OneLoginSelfRegistration -PassThru } }
        @{ Name = 'Users'; Label = 'Creating users, their managers and their roles'; Run = { New-OneLoginUser @userArguments } }
        @{ Name = 'Mfa'; Label = 'Enrolling MFA factors where the account offers them'; Run = { New-OneLoginMfaFactor @tierArguments } }
    )

    $steps = [System.Collections.Generic.List[object]]::new()
    $number = 0

    foreach ($step in $plan) {
        $number++
        if ($Skip -contains $step.Name) {
            Write-Host ('Step {0}: Skipping {1}' -f $number, $step.Name.ToLowerInvariant())
            $steps.Add([PSCustomObject]@{ Name = $step.Name; Attempted = $false; Success = $false; Result = $null; Errors = @() })
            continue
        }

        Write-Host ('Step {0}: {1}' -f $number, $step.Label)

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
            # A step that throws is recorded rather than allowed to end the run, so the steps after
            # it that do not depend on it still happen and the summary says what stopped.
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
    Write-Host ('Operations Completed: {0}/{1}' -f ($attempted.Count - $failed.Count), $attempted.Count)
    Write-Host ('Duration: {0:hh\:mm\:ss}' -f ($endTime - $startTime))
    foreach ($step in $failed) {
        foreach ($message in $step.Errors) { Write-Host ('  ! {0}' -f $message) }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            CorrelationId = $correlationId
            Subdomain     = $connection.Subdomain
            Prefix        = $connection.Prefix
            StartTime     = $startTime
            EndTime       = $endTime
            Duration      = $endTime - $startTime
            Skipped       = @($Skip)
            Steps         = $steps.ToArray()
            Summary       = [PSCustomObject]@{
                TotalSteps      = $steps.Count
                AttemptedSteps  = $attempted.Count
                SuccessfulSteps = $attempted.Count - $failed.Count
                FailedSteps     = $failed.Count
            }
        }
    }
}
