#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    This is the function teardown deletes from, so these are the most important tests in the
    suite. Every one of them is really the same assertion from a different angle: an object
    this module did not create must never be claimed.

    Ownership now has two routes and they are tested separately, because they fail
    differently. Administrative unit membership is authoritative - the container was asked
    what it holds. The name-based fallback is a heuristic, and it is the one that has to be
    conservative, because it is what runs when the container is gone.

    The tenant this module is built for is in real use. It already contains groups named
    "Department Finance" and "IT", applications with ordinary names, and real external guest
    accounts. A prefix match alone would eventually claim one of them.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-EntraSeededObject' -Tag 'Unit', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:TestConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            # The seeded administrative units, returned to any lookup of them. Individual
            # tests override the member and fallback responses around this.
            $script:Units = @(
                [PSCustomObject]@{ id = 'au-users'; displayName = 'ENTRALAB-Users'; description = 'Seeded. [ENTRALAB-seed]' }
                [PSCustomObject]@{ id = 'au-groups'; displayName = 'ENTRALAB-Groups'; description = 'Seeded. [ENTRALAB-seed]' }
                [PSCustomObject]@{ id = 'au-devices'; displayName = 'ENTRALAB-Devices'; description = 'Seeded. [ENTRALAB-seed]' }
                [PSCustomObject]@{ id = 'au-applications'; displayName = 'ENTRALAB-Applications'; description = 'Seeded. [ENTRALAB-seed]' }
            )
            $script:UnitMembers = @()
            $script:Fallback = @()

            # Path-aware, because the function now makes three different kinds of call and a
            # mock that answers them all identically would prove nothing about either route.
            Mock Invoke-EntraRequest {
                if ($Path -eq '/directory/administrativeUnits') { return $script:Units }
                if ($Path -like '/directory/administrativeUnits/*/members/*') { return $script:UnitMembers }
                if ($Path -like '/identity/conditionalAccess/*') { return [PSCustomObject]@{ value = $script:Fallback } }
                return $script:Fallback
            }
        }
    }

    Context 'The container is authoritative' {

        It 'claims whatever the administrative unit holds' {
            InModuleScope TestEnvironment {
                # No name marker at all: membership of a unit this module created is proof on
                # its own, because only this module puts things in it.
                $script:UnitMembers = @([PSCustomObject]@{ id = 'u1'; displayName = 'Anything At All'; userPrincipalName = 'someone@contoso.com' })
                $script:Fallback = @()

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                $result.Count | Should-Be 1
                $result[0].SeedProof | Should-Be 'unit'
            }
        }

        It 'records both routes when the container and the name agree' {
            InModuleScope TestEnvironment {
                $object = [PSCustomObject]@{
                    id                            = 'u1'
                    displayName                   = 'ENTRALAB-Ada Whitfield'
                    userPrincipalName             = 'ENTRALAB-awhitfield@contoso.onmicrosoft.com'
                    onPremisesExtensionAttributes = [PSCustomObject]@{ extensionAttribute15 = 'ENTRALAB-seed' }
                }
                $script:UnitMembers = @($object)
                $script:Fallback = @($object)

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                # Unioned by id, so one object is one result however many routes found it.
                $result.Count | Should-Be 1
                $result[0].SeedProof | Should-MatchString 'unit'
                $result[0].SeedProof | Should-MatchString 'upn'
            }
        }

        It 'falls back to the name when the container has been deleted' {
            InModuleScope TestEnvironment {
                # Without the fallback, deleting the unit would strand everything it held.
                $script:Units = @()
                $script:UnitMembers = @()
                $script:Fallback = @([PSCustomObject]@{
                        id                            = 'u1'
                        displayName                   = 'ENTRALAB-Ada Whitfield'
                        userPrincipalName             = 'ENTRALAB-awhitfield@contoso.onmicrosoft.com'
                        onPremisesExtensionAttributes = [PSCustomObject]@{ extensionAttribute15 = 'ENTRALAB-seed' }
                    })

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                $result.Count | Should-Be 1
                $result[0].SeedProof | Should-Be 'upn+tag'
            }
        }

        It 'uses only the fallback when told to skip the container' {
            InModuleScope TestEnvironment {
                $script:UnitMembers = @([PSCustomObject]@{ id = 'u-only-in-unit'; displayName = 'x'; userPrincipalName = 'x@y.com' })
                $script:Fallback = @()

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection -SkipUnitLookup)
                $result.Count | Should-Be 0
            }
        }
    }

    Context 'Administrative units themselves' {

        It 'claims a unit carrying the prefix and the seed tag' {
            InModuleScope TestEnvironment {
                $result = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $script:TestConnection)
                $result.Count | Should-Be 4
            }
        }

        It 'refuses a unit with the prefix but no tag' {
            InModuleScope TestEnvironment {
                $script:Units = @([PSCustomObject]@{ id = 'real'; displayName = 'ENTRALAB-Something'; description = 'made by hand' })

                $result = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $script:TestConnection -WarningAction SilentlyContinue)
                $result.Count | Should-Be 0
            }
        }

        It 'leaves a real administrative unit alone' {
            InModuleScope TestEnvironment {
                $script:Units = @([PSCustomObject]@{ id = 'real'; displayName = 'Regional Admins EMEA'; description = 'Real container' })

                $result = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $script:TestConnection)
                $result.Count | Should-Be 0
            }
        }
    }

    Context 'The name-based fallback stays conservative' {

        BeforeEach {
            InModuleScope TestEnvironment {
                # The container is empty throughout this context, so every assertion is about
                # the fallback and cannot pass because the unit happened to claim the object.
                $script:UnitMembers = @()
            }
        }

        It 'claims a user carrying only the seed tag, so an interrupted teardown can still find it' {
            InModuleScope TestEnvironment {
                $script:Fallback = @([PSCustomObject]@{
                        id                            = 'u1'
                        displayName                   = 'ENTRALAB-Renamed Later'
                        userPrincipalName             = 'somethingelse@contoso.onmicrosoft.com'
                        onPremisesExtensionAttributes = [PSCustomObject]@{ extensionAttribute15 = 'ENTRALAB-seed' }
                    })

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                $result.Count | Should-Be 1
                $result[0].SeedProof | Should-Be 'tag'
            }
        }

        It 'refuses a user whose name matches the prefix but proves nothing' {
            InModuleScope TestEnvironment {
                $script:Fallback = @([PSCustomObject]@{
                        id                            = 'real1'
                        displayName                   = 'ENTRALAB-Looks Like Ours'
                        userPrincipalName             = 'realperson@contoso.com'
                        onPremisesExtensionAttributes = [PSCustomObject]@{ extensionAttribute15 = $null }
                    })

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                $result.Count | Should-Be 0
            }
        }

        It 'refuses a user with the prefix on the WRONG domain' {
            InModuleScope TestEnvironment {
                $script:Fallback = @([PSCustomObject]@{
                        id                            = 'other1'
                        displayName                   = 'ENTRALAB-Elsewhere'
                        userPrincipalName             = 'ENTRALAB-someone@notourdomain.com'
                        onPremisesExtensionAttributes = [PSCustomObject]@{ extensionAttribute15 = $null }
                    })

                $result = @(Get-EntraSeededObject -Type Users -Connection $script:TestConnection)
                $result.Count | Should-Be 0
            }
        }

        It 'claims a group with both the name prefix and the tag in its description' {
            InModuleScope TestEnvironment {
                $script:Fallback = @([PSCustomObject]@{
                        id = 'g1'; displayName = 'ENTRALAB-Department Finance'
                        description = 'Seeded by EntraEnvironment. Safe to delete. [ENTRALAB-seed]'
                    })

                $result = @(Get-EntraSeededObject -Type Groups -Connection $script:TestConnection)
                $result.Count | Should-Be 1
                $result[0].SeedProof | Should-Be 'name+description'
            }
        }

        It 'refuses a group with the prefix but no tag' {
            InModuleScope TestEnvironment {
                # Groups require BOTH markers precisely because a real group could plausibly
                # satisfy either one alone.
                $script:Fallback = @([PSCustomObject]@{
                        id = 'real-g'; displayName = 'ENTRALAB-Department Finance'
                        description = 'Created by hand by a colleague'
                    })

                $result = @(Get-EntraSeededObject -Type Groups -Connection $script:TestConnection -WarningAction SilentlyContinue)
                $result.Count | Should-Be 0
            }
        }

        It 'refuses an application with the prefix but no tag' {
            InModuleScope TestEnvironment {
                $script:Fallback = @([PSCustomObject]@{
                        id = 'real-a'; appId = 'app2'; displayName = 'ENTRALAB-Real App'; tags = @('SomeOtherTag')
                    })

                $result = @(Get-EntraSeededObject -Type Applications -Connection $script:TestConnection -WarningAction SilentlyContinue)
                $result.Count | Should-Be 0
            }
        }

        It 'refuses a service principal with the prefix but no tag' {
            InModuleScope TestEnvironment {
                # Service principals cannot belong to an administrative unit at all, so the
                # fallback is the only route they have and it has to hold.
                $script:Fallback = @([PSCustomObject]@{
                        id = 'real-sp'; appId = 'app3'; displayName = 'ENTRALAB-Real SP'; tags = @()
                    })

                $result = @(Get-EntraSeededObject -Type ServicePrincipals -Connection $script:TestConnection -WarningAction SilentlyContinue)
                $result.Count | Should-Be 0
            }
        }

        It 'leaves a real Conditional Access policy alone' {
            InModuleScope TestEnvironment {
                $script:Fallback = @(
                    [PSCustomObject]@{ id = 'p1'; displayName = 'ENTRALAB-Require MFA for Seeded Staff' }
                    [PSCustomObject]@{ id = 'p2'; displayName = 'REQUIRE - MFA for All Users' }
                    [PSCustomObject]@{ id = 'p3'; displayName = 'BLOCK - Legacy Authentication' }
                )

                $result = @(Get-EntraSeededObject -Type ConditionalAccessPolicies -Connection $script:TestConnection)
                $result.Count | Should-Be 1
                $result[0].id | Should-Be 'p1'
            }
        }

        It 'does not claim a name that merely starts with the same letters' {
            InModuleScope TestEnvironment {
                # Why the prefix is validated to end in a separator. ENTRALABORATORY starts
                # with ENTRALAB but not with ENTRALAB-.
                $script:Fallback = @([PSCustomObject]@{ id = 'x1'; displayName = 'ENTRALABORATORY Production Policy' })

                $result = @(Get-EntraSeededObject -Type ConditionalAccessPolicies -Connection $script:TestConnection)
                $result.Count | Should-Be 0
            }
        }
    }

    Context 'Query construction' {

        It 'asks the container before it asks the directory' {
            InModuleScope TestEnvironment {
                Get-EntraSeededObject -Type Groups -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-EntraRequest -Times 1 -ParameterFilter {
                    $Path -like '/directory/administrativeUnits/*/members/microsoft.graph.group'
                }
            }
        }

        It 'filters server-side on the prefix rather than listing the directory' {
            InModuleScope TestEnvironment {
                # A client-side scan would make the blast radius of a filter bug the whole
                # tenant rather than one prefix, quite apart from being slow at this volume.
                Get-EntraSeededObject -Type Groups -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-EntraRequest -Times 1 -ParameterFilter {
                    $Path -eq '/groups' -and $Query['$filter'] -eq "startswith(displayName,'ENTRALAB-')"
                }
            }
        }

        It 'queries users by userPrincipalName as well as displayName' {
            InModuleScope TestEnvironment {
                Get-EntraSeededObject -Type Users -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-EntraRequest -Times 1 -ParameterFilter {
                    $Path -eq '/users' -and $Query['$filter'] -eq "startswith(userPrincipalName,'ENTRALAB-')"
                }
            }
        }
    }
}
