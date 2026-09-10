#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown regression tests for the classic -Force-defeats--WhatIf bug. It happens when the
    guards are written as "if ($Force -or $PSCmdlet.ShouldProcess(...))": -or short-circuits, so
    "Remove-... -Force -WhatIf" really deletes everything. Nothing warns you about that; the
    only way to catch it is a test asserting that nothing was deleted.

    The stakes are as high as they get here, because a deleted Okta user cannot be restored at
    all - there is no recycle bin.

    Every call is mocked. This suite must never reach a tenant.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-OktaEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{
                    OrgUrl              = 'https://trial-123456.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                    ActiveUserLimit     = 10
                    SeedMarker          = '[OKTALAB-seed]'
                    SeedTag          = 'OKTALAB-seed'
                }
            }
            Mock Write-TestMessage { }
            Mock New-OktaProfileAttribute { [PSCustomObject]@{ Removed = @('labSeedTag'); Errors = @() } }

            Mock Get-OktaSeededUser {
                @([PSCustomObject]@{
                    id      = 'u1'
                    status  = 'ACTIVE'
                    profile = [PSCustomObject]@{ login = 'awhitfield@oktalab.example.com' }
                })
            }
            Mock Get-OktaSeededGroup {
                @([PSCustomObject]@{
                    id      = 'g1'
                    type    = 'OKTA_GROUP'
                    profile = [PSCustomObject]@{
                        name        = 'OKTALAB-All Employees'
                        description = 'Everyone [seed:OKTALAB]'
                    }
                })
            }

            # Must honour -IncludeServiceApp. Returning the service app to the lab-app sweep as
            # well is what -Keep ServiceApp exists to prevent, so a mock that ignores the switch
            # tests the opposite of the intended behaviour.
            Mock Get-OktaSeededApp {
                if ($IncludeServiceApp) {
                    return @([PSCustomObject]@{
                        id = 'a1'; label = 'OKTALAB Test Environment Automation'; status = 'ACTIVE'
                    })
                }
                return @()
            }

            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/groups/rules') {
                    return @([PSCustomObject]@{ id = 'r1'; name = 'OKTALAB-Rule-Contractors'; status = 'ACTIVE' })
                }
                # Each of these returns one object of ours and one belonging to somebody else,
                # so every sweep is asserted on what it leaves behind as well as what it takes.
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/eventHooks') {
                    return @(
                        [PSCustomObject]@{ id = 'h1'; name = 'OKTALAB-Lifecycle-Watcher' }
                        [PSCustomObject]@{ id = 'h2'; name = 'Production SIEM Feed' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/trustedOrigins') {
                    return @(
                        [PSCustomObject]@{ id = 'o1'; name = 'OKTALAB-Lab-Portal' }
                        [PSCustomObject]@{ id = 'o2'; name = 'Corporate SPA' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') {
                    if ($Query.type -eq 'OKTA_SIGN_ON') {
                        return @(
                            [PSCustomObject]@{ id = 'p1'; name = 'OKTALAB-Admin-Session' }
                            [PSCustomObject]@{ id = 'p2'; name = 'Default Policy' }
                        )
                    }
                    return @([PSCustomObject]@{ id = 'p3'; name = 'OKTALAB-Contractor-Password' })
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') {
                    return @(
                        [PSCustomObject]@{ id = 'z1'; name = 'OKTALAB-Corporate-Egress' }
                        [PSCustomObject]@{ id = 'z2'; name = 'LegacyVPN' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/schemas/user/linkedObjects') {
                    return @([PSCustomObject]@{ primary = @{ name = 'labMentor' } })
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/types/user') {
                    return @(
                        [PSCustomObject]@{ id = 't0'; name = 'user'; default = $true }
                        [PSCustomObject]@{ id = 't1'; name = 'oktalabContractor'; default = $false }
                    )
                }
                return $null
            }
        }
    }

    Context 'WhatIf must win over Force' {

        It 'deletes no users' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/users/'
                }
            }
        }

        It 'does not even deactivate a user' {
            # The quieter half of the same bug. A deactivation that -WhatIf was meant to skip
            # locks eight people out and reports that it did nothing.
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'POST' -and $Path -match '/lifecycle/deactivate$'
                }
            }
        }

        It 'deletes no groups' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/groups/'
                }
            }
        }

        It 'deletes no group rules' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/groups/rules/'
                }
            }
        }

        It 'deletes no apps' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/apps/'
                }
            }
        }

        It 'reports nothing removed' {
            InModuleScope TestEnvironment {
                $result = Remove-OktaEnvironment -Force -WhatIf -PassThru
                @($result.Users.Removed).Count | Should-Be 0
                @($result.Groups.Removed).Count | Should-Be 0
            }
        }

        It 'does not delete the credential file' {
            InModuleScope TestEnvironment {
                Mock Remove-Item { }
                Mock Test-Path { $true }

                $null = Remove-OktaEnvironment -Force -WhatIf -RemoveCredentialFile

                Should-NotInvoke Remove-Item
            }
        }
    }

    Context 'Force actually removes' {

        # The counterpart to the tests above: proving -WhatIf is honoured is worthless if the
        # real path stopped working too.

        It 'deactivates and then deletes each user' {
            # Okta needs both. A single DELETE against an active user only deactivates it, so
            # a teardown that skips the deactivate leaves the user behind still holding a
            # licence slot, and reports success.
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/api/v1/users/u1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/users/u1'
                }
            }
        }

        It 'deletes the groups' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/groups/g1'
                }
            }
        }

        It 'deactivates a group rule before deleting it' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/api/v1/groups/rules/r1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/groups/rules/r1'
                }
            }
        }

        It 'removes the custom schema attributes last' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force
                Should-Invoke New-OktaProfileAttribute -Times 1 -Exactly
            }
        }

        It 'keeps the credential file unless asked to delete it' {
            InModuleScope TestEnvironment {
                Mock Remove-Item { }
                Mock Test-Path { $true }

                $null = Remove-OktaEnvironment -Force

                Should-NotInvoke Remove-Item
            }
        }
    }

    Context 'The sweeps added for policies, zones, hooks, origins, types and links' {

        # These went in without tests, in the one function where deleting the wrong thing is
        # unrecoverable. Each case asserts both halves: ours goes, theirs stays.

        It 'deletes our event hook and leaves the production one' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/eventHooks/h1'
                }
                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/eventHooks/h2'
                }
            }
        }

        It 'deletes our trusted origin and leaves the corporate one' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/trustedOrigins/o1'
                }
                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/trustedOrigins/o2'
                }
            }
        }

        It 'deletes both our policies and leaves the org default' {
            # The policy sweep queries per type, because there is no "all policies" listing.
            # A sweep that forgot PASSWORD would leave that one behind and still report success.
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p1'
                }
                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p3'
                }
                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p2'
                }
            }
        }

        It 'deletes our network zone and leaves the unrelated one' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/zones/z1'
                }
                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/zones/z2'
                }
            }
        }

        It 'deletes the linked object definition' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and
                    $Path -eq '/api/v1/meta/schemas/user/linkedObjects/labMentor'
                }
            }
        }

        It 'deletes our user type and never the default one' {
            # Deleting the default user type would take every user in the org with it.
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/meta/types/user/t1'
                }
                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/meta/types/user/t0'
                }
            }
        }

        It 'removes zones only after the policies that reference them' {
            # Okta refuses to delete a zone a policy rule still points at, so the order is a
            # correctness requirement rather than a preference.
            InModuleScope TestEnvironment {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'DELETE' -and $Path -like '/api/v1/policies/*') {
                        $script:Order.Add('policy')
                    }
                    if ($Method -eq 'DELETE' -and $Path -like '/api/v1/zones/*') {
                        $script:Order.Add('zone')
                    }
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') {
                        return @([PSCustomObject]@{ id = 'p1'; name = 'OKTALAB-Admin-Session' })
                    }
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') {
                        return @([PSCustomObject]@{ id = 'z1'; name = 'OKTALAB-Corporate-Egress' })
                    }
                    return $null
                }

                $null = Remove-OktaEnvironment -Force

                $script:Order.IndexOf('policy') | Should-BeLessThan $script:Order.IndexOf('zone')
            }
        }

        It 'removes nothing new under -Force -WhatIf either' {
            # The -WhatIf guarantee has to hold for the sweeps added later, not just the
            # original four.
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -WhatIf

                # Not $path: inside a ParameterFilter that name is the bound parameter, so the
                # comparison would be against itself.
                foreach ($expectedPath in @('/api/v1/eventHooks/h1', '/api/v1/trustedOrigins/o1',
                        '/api/v1/policies/p1', '/api/v1/zones/z1',
                        '/api/v1/meta/types/user/t1',
                        '/api/v1/meta/schemas/user/linkedObjects/labMentor')) {
                    Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                        $Method -eq 'DELETE' -and $Path -eq $expectedPath
                    }
                }
            }
        }

        It 'honours -Keep for each of them individually' {
            InModuleScope TestEnvironment {
                $keep = @('EventHooks', 'TrustedOrigins', 'Policies', 'NetworkZones',
                    'LinkedObjects', 'UserTypes')
                $null = Remove-OktaEnvironment -Force -Keep $keep

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter { $Method -eq 'DELETE' -and
                    ($Path -like '/api/v1/eventHooks/*' -or $Path -like '/api/v1/trustedOrigins/*' -or
                     $Path -like '/api/v1/policies/*' -or $Path -like '/api/v1/zones/*' -or
                     $Path -like '/api/v1/meta/types/user/*' -or $Path -like '*linkedObjects/*') }
            }
        }
    }

    Context 'Keep' {

        It 'leaves the service app alone when kept, so the next seed can still authenticate' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -Keep ServiceApp

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/apps/'
                }
            }
        }

        It 'leaves the schema alone when kept' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -Keep Schema
                Should-NotInvoke New-OktaProfileAttribute
            }
        }

        It 'still removes users when only the app is kept' {
            InModuleScope TestEnvironment {
                $null = Remove-OktaEnvironment -Force -Keep ServiceApp

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/users/u1'
                }
            }
        }
    }
}
