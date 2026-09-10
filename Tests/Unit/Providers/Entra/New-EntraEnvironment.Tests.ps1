#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The orchestrator's job is ordering and isolation, so that is what these test.

    Two steps bracket the rest and both matter. Administrative units are created first because
    nothing can be placed in a container that does not exist yet, and the containment
    reconciliation runs last because placement loses races with replication and an object that
    exists but was never contained looks entirely healthy until teardown.

    The backstop in the final Context is the important one, and it is there because of a defect
    in the Okta module's suite: a step was added to the orchestrator without a mock, and those
    tests quietly made real network calls for a while. A suite whose central promise is "this
    reaches no tenant" has to enforce that promise rather than assert it in a comment.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraEnvironment' -Tag 'Unit' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:EntraConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                TenantName     = 'Contoso'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()

            Mock New-EntraAdministrativeUnit { $script:StepOrder.Add('AdministrativeUnits'); @([PSCustomObject]@{ Key = 'au' }) }
            Mock New-EntraUser { $script:StepOrder.Add('Users'); @([PSCustomObject]@{ Key = 'u' }) }
            Mock New-EntraGroup { $script:StepOrder.Add('Groups'); @([PSCustomObject]@{ Key = 'g' }) }
            Mock New-EntraGuestUser { $script:StepOrder.Add('GuestUsers'); @([PSCustomObject]@{ Key = 'gu' }) }
            Mock Set-EntraLicense { $script:StepOrder.Add('Licenses'); @([PSCustomObject]@{ Target = 'l' }) }
            Mock New-EntraDevice { $script:StepOrder.Add('Devices'); @([PSCustomObject]@{ Key = 'd' }) }
            Mock New-EntraApplication { $script:StepOrder.Add('Applications'); @([PSCustomObject]@{ Key = 'a' }) }
            Mock New-EntraNamedLocation { $script:StepOrder.Add('NamedLocations'); @([PSCustomObject]@{ Key = 'n' }) }
            Mock New-EntraConditionalAccessPolicy { $script:StepOrder.Add('ConditionalAccessPolicies'); @([PSCustomObject]@{ Key = 'p' }) }
            Mock New-EntraDirectoryExtension { $script:StepOrder.Add('DirectoryExtensions'); @([PSCustomObject]@{ Key = 'x' }) }
            Mock New-EntraDirectoryRole { $script:StepOrder.Add('DirectoryRoles'); @([PSCustomObject]@{ Key = 'r' }) }
            Mock New-EntraRoleEligibility { $script:StepOrder.Add('RoleEligibilities'); @([PSCustomObject]@{ Key = 'e' }) }
            Mock New-EntraAuthenticationStrength { $script:StepOrder.Add('AuthenticationStrengths'); @([PSCustomObject]@{ Key = 's' }) }
            Mock Update-EntraContainment { $script:StepOrder.Add('Containment'); @([PSCustomObject]@{ ObjectType = 'Users' }) }
        }
    }

    Context 'Ordering' {

        It 'runs the steps in the only order their dependencies allow' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null

                @($script:StepOrder) | Should-BeCollection @(
                    'AdministrativeUnits', 'Users', 'Groups', 'GuestUsers', 'Licenses', 'Devices',
                    'Applications', 'DirectoryExtensions', 'DirectoryRoles', 'RoleEligibilities',
                    'NamedLocations', 'AuthenticationStrengths', 'ConditionalAccessPolicies',
                    'Containment')
            }
        }

        It 'creates the containers before anything that goes in them' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('AdministrativeUnits') | Should-Be 0
            }
        }

        It 'reconciles containment last, once everything has been created' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('Containment') | Should-Be ($script:StepOrder.Count - 1)
            }
        }

        It 'creates users before groups, because membership needs them' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('Users') | Should-BeLessThan $script:StepOrder.IndexOf('Groups')
            }
        }

        It 'creates the guests after the groups, because they join them rather than being listed by them' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('Groups') | Should-BeLessThan $script:StepOrder.IndexOf('GuestUsers')
            }
        }

        It 'creates the role definitions before anything is made eligible for them' {
            InModuleScope TestEnvironment {
                # The other way round, the eligibility step has nothing to point at and skips
                # every row - which looks like success, because skipping is how it handles a
                # role it did not create.
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('DirectoryRoles') |
                    Should-BeLessThan $script:StepOrder.IndexOf('RoleEligibilities')
            }
        }

        It 'creates named locations before the policies that condition on them' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment | Out-Null
                $script:StepOrder.IndexOf('NamedLocations') |
                    Should-BeLessThan $script:StepOrder.IndexOf('ConditionalAccessPolicies')
            }
        }
    }

    Context 'Skip' {

        It 'leaves out a skipped step' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment -Skip Devices | Out-Null

                @($script:StepOrder) | Should-NotContainCollection @('Devices')
                Should-NotInvoke New-EntraDevice
            }
        }

        It 'leaves out several skipped steps and still runs the rest in order' {
            InModuleScope TestEnvironment {
                New-EntraEnvironment -Skip NamedLocations, ConditionalAccessPolicies | Out-Null

                @($script:StepOrder) | Should-BeCollection @(
                    'AdministrativeUnits', 'Users', 'Groups', 'GuestUsers', 'Licenses', 'Devices',
                    'Applications', 'DirectoryExtensions', 'DirectoryRoles', 'RoleEligibilities',
                    'AuthenticationStrengths', 'Containment')
            }
        }

        It 'reports a skipped step as skipped rather than omitting it from the result' {
            InModuleScope TestEnvironment {
                $result = New-EntraEnvironment -Skip Devices -PassThru

                $devices = $result.Steps | Where-Object { $_.Step -eq 'Devices' }
                $devices.Status | Should-Be 'Skipped'
                $devices.Count | Should-Be 0
            }
        }

        It 'rejects a step name it does not know' {
            InModuleScope TestEnvironment {
                { New-EntraEnvironment -Skip 'NotAStep' } | Should-Throw
            }
        }
    }

    Context 'Failure isolation' {

        It 'continues after a failing step rather than abandoning a half-seeded tenant' {
            InModuleScope TestEnvironment {
                Mock New-EntraGroup { throw 'Graph said no' }

                $result = New-EntraEnvironment -PassThru -WarningAction SilentlyContinue

                # Everything downstream of the failure still ran, including the containment
                # pass, which is what makes a partially failed seed still cleanable.
                @($script:StepOrder) | Should-ContainCollection @('Containment')

                $groups = $result.Steps | Where-Object { $_.Step -eq 'Groups' }
                $groups.Status | Should-Be 'Failed'
                $groups.Error | Should-MatchString 'Graph said no'
            }
        }

        It 'reports the total across the steps that succeeded' {
            InModuleScope TestEnvironment {
                Mock New-EntraGroup { throw 'Graph said no' }

                $result = New-EntraEnvironment -PassThru -WarningAction SilentlyContinue

                # Fourteen steps returning one object each, less the one that failed.
                $result.TotalCount | Should-Be 13
            }
        }
    }

    Context 'Result' {

        It 'names the tenant it seeded and the namespace it used' {
            InModuleScope TestEnvironment {
                $result = New-EntraEnvironment -PassThru

                $result.TenantName | Should-Be 'Contoso'
                $result.Prefix | Should-Be 'ENTRALAB-'
                $result.UpnSuffix | Should-Be 'contoso.onmicrosoft.com'
            }
        }

        It 'returns nothing without -PassThru' {
            InModuleScope TestEnvironment {
                $result = New-EntraEnvironment
                $result | Should-BeNull
            }
        }
    }

    Context 'The suite reaches no tenant' {

        It 'makes no HTTP call, whatever steps the orchestrator gains later' {
            InModuleScope TestEnvironment {
                # The backstop. If a step is added to the orchestrator and its mock is
                # forgotten, this fails loudly here instead of silently seeding somebody's
                # directory during a unit test run.
                Mock Invoke-WebRequest { throw 'A unit test attempted a real HTTP request.' }
                Mock Invoke-RestMethod { throw 'A unit test attempted a real HTTP request.' }

                New-EntraEnvironment -PassThru | Out-Null

                Should-NotInvoke Invoke-WebRequest
                Should-NotInvoke Invoke-RestMethod
            }
        }
    }
}
