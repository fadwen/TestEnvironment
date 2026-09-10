#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The orchestrator's job is ordering and honesty. Groups must exist before users join
    them and applications before policies bind to them, so the order is asserted rather than
    assumed. And a step that returned an object full of errors has not succeeded, whatever
    the absence of an exception suggests, so the failure count is asserted against the Errors
    property. The backstop mock is the reason this suite can never reach an instance: a step
    added later and left unmocked throws rather than calling out.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Test-AuthentikPrerequisite { $true }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-AuthentikGroup { $script:StepOrder.Add('Groups'); [PSCustomObject]@{ CreatedGroups = 9; UpdatedGroups = 0; Errors = @() } }
            Mock New-AuthentikUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ CreatedUsers = 10; UpdatedUsers = 0; Errors = @() } }
            Mock New-AuthentikRole { $script:StepOrder.Add('Roles'); [PSCustomObject]@{ CreatedRoles = 3; GroupsAssigned = 2; Errors = @() } }
            Mock New-AuthentikApplication { $script:StepOrder.Add('Applications'); [PSCustomObject]@{ CreatedApplications = 9; ProvidersCreated = 8; Errors = @() } }
            Mock New-AuthentikOutpost { $script:StepOrder.Add('Outposts'); [PSCustomObject]@{ CreatedOutposts = 3; Errors = @() } }
            Mock New-AuthentikFlow { $script:StepOrder.Add('Flows'); [PSCustomObject]@{ CreatedFlows = 3; StagesCreated = 6; ProvidersUpdated = 3; Errors = @() } }
            Mock New-AuthentikScopeMapping { $script:StepOrder.Add('ScopeMappings'); [PSCustomObject]@{ CreatedMappings = 3; ProvidersUpdated = 2; Errors = @() } }
            Mock New-AuthentikEntitlement { $script:StepOrder.Add('Entitlements'); [PSCustomObject]@{ CreatedEntitlements = 6; Errors = @() } }
            Mock New-AuthentikPolicy { $script:StepOrder.Add('Policies'); [PSCustomObject]@{ CreatedPolicies = 7; BindingsCreated = 5; Errors = @() } }
            Mock New-AuthentikNotificationRule { $script:StepOrder.Add('NotificationRules'); [PSCustomObject]@{ CreatedRules = 2; TransportsCreated = 2; Errors = @() } }
            Mock New-AuthentikBinding { $script:StepOrder.Add('Bindings'); [PSCustomObject]@{ CreatedBindings = 11; ExistingBindings = 0; Errors = @() } }
            Mock New-AuthentikToken { $script:StepOrder.Add('Tokens'); [PSCustomObject]@{ CreatedTokens = 3; Errors = @() } }
            Mock New-AuthentikInvitation { $script:StepOrder.Add('Invitations'); [PSCustomObject]@{ CreatedInvitations = 3; Errors = @() } }

            # The backstop. A step added later and not mocked here throws rather than reaching
            # whatever instance the developer is pointed at.
            Mock Invoke-AuthentikRequest { throw "A network call escaped the mocks: $Method $Path" }
        }
    }

    It 'runs the steps in dependency order' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikEnvironment -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Groups', 'Users', 'Roles', 'Applications', 'Outposts', 'Flows', 'ScopeMappings', 'Entitlements', 'Policies', 'NotificationRules', 'Bindings', 'Tokens', 'Invitations')
        }
    }

    It 'skips what it is told to and attempts the rest' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikEnvironment -Skip Policies, NotificationRules -PassThru -Confirm:$false

            $script:StepOrder | Should-BeCollection @('Groups', 'Users', 'Roles', 'Applications', 'Outposts', 'Flows', 'ScopeMappings', 'Entitlements', 'Bindings', 'Tokens', 'Invitations')
            $r.Operations.Policies.Attempted | Should-BeFalse
            $r.Summary.TotalOperations | Should-Be 11
            $r.Summary.SuccessfulOperations | Should-Be 11
        }
    }

    It 'counts a step that returned errors as failed, even though it did not throw' {
        InModuleScope TestEnvironment {
            Mock New-AuthentikUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ CreatedUsers = 8; Errors = @('two users failed') } }

            $r = New-AuthentikEnvironment -PassThru -Confirm:$false -ErrorAction SilentlyContinue

            $r.Operations.Users.Success | Should-BeFalse
            $r.Summary.FailedOperations | Should-Be 1
            $r.Summary.SuccessfulOperations | Should-Be 12
        }
    }

    It 'keeps going when a step throws' {
        InModuleScope TestEnvironment {
            Mock New-AuthentikApplication { throw 'flows missing' }

            $r = New-AuthentikEnvironment -PassThru -Confirm:$false -ErrorAction SilentlyContinue

            $r.Operations.Applications.Results | Should-MatchString 'flows missing'
            $script:StepOrder | Should-ContainCollection @('Policies', 'NotificationRules')
        }
    }

    It 'passes the account password through to the users step only' {
        InModuleScope TestEnvironment {
            $password = New-Object System.Security.SecureString
            foreach ($c in 'Lab-Pass-1'.ToCharArray()) { $password.AppendChar($c) }

            $null = New-AuthentikEnvironment -AccountPassword $password -Confirm:$false

            Should-Invoke New-AuthentikUser -Times 1 -Exactly -ParameterFilter { $null -ne $AccountPassword }
        }
    }

    Context 'The suite reaches no instance' {
        It 'makes no HTTP call, whatever steps the orchestrator gains later' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { throw 'A unit test attempted a real HTTP request.' }
                Mock Invoke-RestMethod { throw 'A unit test attempted a real HTTP request.' }

                New-AuthentikEnvironment -PassThru -Confirm:$false | Out-Null

                Should-NotInvoke Invoke-WebRequest
                Should-NotInvoke Invoke-RestMethod
            }
        }
    }
}
