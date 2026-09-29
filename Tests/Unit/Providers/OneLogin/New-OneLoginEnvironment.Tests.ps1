#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The orchestrator's job is ordering and honesty. Fields must exist before people carry the tag,
    roles before apps are granted to them and mappings add them, and mappings before people so an
    enabled one acts on each person as they are created; so the order is asserted rather than
    assumed. A step that returned errors has not succeeded. -Tier reaches every step that decides
    what exists, and a seed with no -Tier passes none - which is pinned because the first live seed
    passed $null, failed four ValidateSets and skipped roles, groups, apps and mappings entirely.

    The backstop mock is the reason this suite can never reach an account.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'New-OneLoginEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' } }
            Mock Write-TestMessage { }
            Mock Write-Host { }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-OneLoginCustomAttribute { $script:StepOrder.Add('Attributes'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginRole { $script:StepOrder.Add('Roles'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginGroup { $script:StepOrder.Add('Groups'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginApp { $script:StepOrder.Add('Apps'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginMapping { $script:StepOrder.Add('Mappings'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginPolicy { $script:StepOrder.Add('Policies'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginAppRule { $script:StepOrder.Add('AppRules'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginApiAuthorization { $script:StepOrder.Add('ApiAuthorizations'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginSmartHook { $script:StepOrder.Add('Hooks'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginSelfRegistration { $script:StepOrder.Add('SelfRegistration'); [PSCustomObject]@{ Errors = @() } }
            Mock New-OneLoginMfaFactor { $script:StepOrder.Add('Mfa'); [PSCustomObject]@{ Errors = @() } }

            # The backstop. A step added later and not mocked here throws rather than reaching
            # whatever account the developer is connected to.
            Mock Invoke-OneLoginRequest { throw "A network call escaped the mocks: $Method $Path" }
        }
    }

    It 'runs the steps in dependency order' {
        InModuleScope TestEnvironment {
            $null = New-OneLoginEnvironment -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Attributes', 'Roles', 'Groups', 'Policies', 'Apps', 'AppRules', 'ApiAuthorizations', 'Mappings', 'Hooks', 'SelfRegistration', 'Users', 'Mfa')
        }
    }

    It 'skips what it is told to and attempts the rest' {
        InModuleScope TestEnvironment {
            $r = New-OneLoginEnvironment -Skip Apps, Mappings, Hooks -PassThru -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Attributes', 'Roles', 'Groups', 'Policies', 'AppRules', 'ApiAuthorizations', 'SelfRegistration', 'Users', 'Mfa')
            $r.Summary.TotalSteps | Should-Be 12
            $r.Summary.AttemptedSteps | Should-Be 9
            @($r.Skipped) | Should-BeCollection @('Apps', 'Mappings', 'Hooks')
        }
    }

    It 'counts a step that returned errors as failed, and keeps going past one that throws' {
        InModuleScope TestEnvironment {
            Mock New-OneLoginUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ Errors = @('7 people were made Unlicensed') } }
            Mock New-OneLoginGroup { $script:StepOrder.Add('Groups'); throw 'plan limit' }

            $r = New-OneLoginEnvironment -PassThru -Confirm:$false -WarningAction SilentlyContinue

            @($r.Steps | Where-Object Name -eq 'Users').Success | Should-BeFalse
            @($r.Steps | Where-Object Name -eq 'Groups')[0].Errors[0] | Should-MatchString 'plan limit'
            $script:StepOrder | Should-ContainCollection @('Apps', 'Mappings', 'Users')
            $r.Summary.FailedSteps | Should-Be 2
            $r.Summary.SuccessfulSteps | Should-Be 10
        }
    }

    It 'passes -Tier to every step that decides what exists, and -ShowProgress to the users step' {
        InModuleScope TestEnvironment {
            $null = New-OneLoginEnvironment -Tier Core -ShowProgress -Confirm:$false
            foreach ($step in 'New-OneLoginRole', 'New-OneLoginGroup', 'New-OneLoginPolicy', 'New-OneLoginApp', 'New-OneLoginAppRule', 'New-OneLoginMapping', 'New-OneLoginSmartHook', 'New-OneLoginMfaFactor') {
                Should-Invoke $step -Times 1 -Exactly -ParameterFilter { @($Tier) -eq 'Core' }
            }
            # What a tier cannot change - an API and a sign-up profile exist for nobody in particular - takes none.
            Should-Invoke New-OneLoginApiAuthorization -Times 1 -Exactly
            Should-Invoke New-OneLoginSelfRegistration -Times 1 -Exactly
            Should-Invoke New-OneLoginUser -Times 1 -Exactly -ParameterFilter { @($Tier) -eq 'Core' -and $ShowProgress }
            Should-Invoke New-OneLoginCustomAttribute -Times 1 -Exactly
        }
    }

    It 'passes no -Tier at all when none was given' {
        InModuleScope TestEnvironment {
            $null = New-OneLoginEnvironment -Confirm:$false
            foreach ($step in 'New-OneLoginRole', 'New-OneLoginGroup', 'New-OneLoginPolicy', 'New-OneLoginApp', 'New-OneLoginAppRule', 'New-OneLoginMapping', 'New-OneLoginSmartHook', 'New-OneLoginUser', 'New-OneLoginMfaFactor') {
                Should-Invoke $step -Times 1 -Exactly -ParameterFilter { $null -eq $Tier }
            }
        }
    }

    It 'returns nothing without -PassThru' {
        InModuleScope TestEnvironment {
            @(New-OneLoginEnvironment -Confirm:$false) | Should-BeCollection -Count 0
        }
    }

    It 'makes no HTTP call, whatever steps the orchestrator gains later' {
        InModuleScope TestEnvironment {
            Mock Invoke-WebRequest { throw 'A unit test attempted a real HTTP request.' }
            Mock Invoke-RestMethod { throw 'A unit test attempted a real HTTP request.' }
            $null = New-OneLoginEnvironment -PassThru -Confirm:$false
            Should-NotInvoke Invoke-WebRequest
            Should-NotInvoke Invoke-RestMethod
            Should-NotInvoke Invoke-OneLoginRequest
        }
    }
}

Describe 'Get-OneLoginSeedScope' -Tag 'Unit', 'Private' {

    It 'with every tier, covers every role and group the data declares; with Bulk alone, none' {
        # Bulk people are unlicensed and hold no roles, and every role and group has a Core member,
        # so a Bulk-only seed creates no role at all rather than creating one it could never prove.
        InModuleScope TestEnvironment {
            $data = Get-OneLoginDataPath
            $roles = @(Import-Csv -LiteralPath (Join-Path $data 'OneLoginRoles.csv') -Encoding UTF8).Key
            $groups = @(Import-Csv -LiteralPath (Join-Path $data 'OneLoginGroups.csv') -Encoding UTF8).Key

            $all = Get-OneLoginSeedScope
            @($roles | Where-Object { -not $all.Roles.Contains($_) }) | Should-BeCollection -Count 0
            @($groups | Where-Object { -not $all.Groups.Contains($_) }) | Should-BeCollection -Count 0

            $core = Get-OneLoginSeedScope -Tier Core
            $core.Roles.Count | Should-Be $roles.Count

            (Get-OneLoginSeedScope -Tier Bulk).Roles.Count | Should-Be 0
        }
    }
}
