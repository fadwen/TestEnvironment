#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The orchestrator's job is ordering and honesty. Attributes must exist before users carry
    them, populations and groups before users join them, and resources before applications are
    granted their scopes, so the order is asserted rather than assumed. A step that returned an
    object full of errors has not succeeded, whatever the absence of an exception suggests, so
    the failure count is asserted against the Errors property. The backstop mock is the reason
    this suite can never reach an environment: a step added later and left unmocked throws
    rather than calling out.

    Every call is mocked. This suite must never reach an environment.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}


Describe 'New-PingOneEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-PingOneConnection {
                @{ EnvironmentId = '11111111-1111-1111-1111-111111111111'; EnvironmentName = 'Sandbox'; Prefix = 'ZZ-TEST-'; EmailDomain = 'pingonelab.example.com' }
            }
            Mock Write-TestMessage { }
            Mock Write-Host { }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-PingOneProfileAttribute { $script:StepOrder.Add('Attributes'); [PSCustomObject]@{ Created = @(1, 2, 3, 4, 5); Errors = @() } }
            Mock New-PingOnePopulation { $script:StepOrder.Add('Populations'); [PSCustomObject]@{ Created = @(1, 2, 3, 4); Errors = @() } }
            Mock New-PingOneGroup { $script:StepOrder.Add('Groups'); [PSCustomObject]@{ Created = @(1..11); Errors = @() } }
            Mock New-PingOneUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ Created = @(1..19); Errors = @() } }
            Mock New-PingOneResource { $script:StepOrder.Add('Resources'); [PSCustomObject]@{ Created = @(1, 2); Errors = @() } }
            Mock New-PingOneApplication { $script:StepOrder.Add('Applications'); [PSCustomObject]@{ Created = @(1..6); Errors = @() } }

            # The backstop. A step added later and not mocked here throws rather than reaching
            # whatever environment the developer is connected to.
            Mock Invoke-PingOneRequest { throw "A network call escaped the mocks: $Method $Path" }
        }
    }

    It 'runs the steps in dependency order' {
        InModuleScope TestEnvironment {
            $null = New-PingOneEnvironment -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Attributes', 'Populations', 'Groups', 'Users', 'Resources', 'Applications')
        }
    }

    It 'skips what it is told to and attempts the rest' {
        InModuleScope TestEnvironment {
            $r = New-PingOneEnvironment -Skip Resources, Applications -PassThru -Confirm:$false

            $script:StepOrder | Should-BeCollection @('Attributes', 'Populations', 'Groups', 'Users')
            @($r.Steps | Where-Object Name -eq 'Resources').Attempted | Should-BeFalse
            $r.Summary.TotalSteps | Should-Be 6
            $r.Summary.AttemptedSteps | Should-Be 4
            $r.Summary.SuccessfulSteps | Should-Be 4
        }
    }

    It 'counts a step that returned errors as failed, even though it did not throw' {
        InModuleScope TestEnvironment {
            Mock New-PingOneUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ Created = @(1..17); Errors = @('two users failed') } }

            $r = New-PingOneEnvironment -PassThru -Confirm:$false

            @($r.Steps | Where-Object Name -eq 'Users').Success | Should-BeFalse
            $r.Summary.FailedSteps | Should-Be 1
            $r.Summary.SuccessfulSteps | Should-Be 5
        }
    }

    It 'keeps going when a step throws, and records what stopped it' {
        InModuleScope TestEnvironment {
            Mock New-PingOneGroup { $script:StepOrder.Add('Groups'); throw 'population missing' }

            $r = New-PingOneEnvironment -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $groups = @($r.Steps | Where-Object Name -eq 'Groups')[0]
            $groups.Attempted | Should-BeTrue
            $groups.Success | Should-BeFalse
            $groups.Errors[0] | Should-MatchString 'population missing'
            $script:StepOrder | Should-ContainCollection @('Users', 'Resources', 'Applications')
            $r.Summary.FailedSteps | Should-Be 1
        }
    }

    It 'passes -Tier and -ShowProgress to the users step and nowhere else' {
        InModuleScope TestEnvironment {
            $null = New-PingOneEnvironment -Tier Core -ShowProgress -Confirm:$false

            Should-Invoke New-PingOneUser -Times 1 -Exactly -ParameterFilter { @($Tier) -eq 'Core' -and $ShowProgress }
            Should-Invoke New-PingOneGroup -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Tier') }
        }
    }

    It 'returns nothing without -PassThru' {
        InModuleScope TestEnvironment {
            @(New-PingOneEnvironment -Confirm:$false) | Should-BeCollection -Count 0
        }
    }

    Context 'The suite reaches no environment' {
        It 'makes no HTTP call, whatever steps the orchestrator gains later' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { throw 'A unit test attempted a real HTTP request.' }
                Mock Invoke-RestMethod { throw 'A unit test attempted a real HTTP request.' }

                $null = New-PingOneEnvironment -PassThru -Confirm:$false

                Should-NotInvoke Invoke-WebRequest
                Should-NotInvoke Invoke-RestMethod
                Should-NotInvoke Invoke-PingOneRequest
            }
        }
    }
}
