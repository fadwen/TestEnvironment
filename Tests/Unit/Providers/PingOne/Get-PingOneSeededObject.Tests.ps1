#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Ownership discovery for the PingOne provider - the only thing teardown deletes from.

    The rule this module holds across every provider is that nothing is deleted for merely
    matching a name. For PingOne that means the tag in the description AND the prefix on the
    name, platform objects refused by type whatever they say, users proved by their population
    before the tag, and custom attributes proved only when this module declared them.

    Every call is mocked. This suite must never reach an environment.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-PingOneSeededObject' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{
                EnvironmentId = '00000000-0000-4000-8000-000000000001'
                Prefix        = 'ZZ-TEST-'
                EmailDomain   = 'pingonelab.example.com'
            }

            # The backstop. A call no test mocked would otherwise run the real function and reach
            # PingOne. It fails loudly instead, naming the path, because a suite that quietly makes
            # network calls can go unnoticed for a long time. Every parameter-filtered mock below
            # takes precedence over this one.
            Mock Invoke-PingOneRequest { throw "Escaped the mocks: $Method $Path" }
        }
    }

    Context 'Tag and prefix are both required' {

        It 'claims a group carrying both' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'groups' } {
                    [PSCustomObject]@{ id = 'g1'; name = 'ZZ-TEST-Staff'; description = 'Everyone ZZ-TEST-seed' }
                }
                @(Get-PingOneSeededObject -Type Groups -Connection $script:Connection).id | Should-BeCollection @('g1')
            }
        }

        It 'refuses a group with the tag but not the prefix' {
            # The tag alone could be pasted into a real group's description by accident.
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'groups' } {
                    [PSCustomObject]@{ id = 'real'; name = 'Finance'; description = 'Copied from a wiki: ZZ-TEST-seed' }
                }
                @(Get-PingOneSeededObject -Type Groups -Connection $script:Connection) | Should-BeCollection -Count 0
            }
        }

        It 'refuses a group with the prefix but not the tag' {
            # Prefix alone is exactly the name matching this module refuses to do.
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'groups' } {
                    [PSCustomObject]@{ id = 'lookalike'; name = 'ZZ-TEST-Staff'; description = 'Made by a person' }
                }
                @(Get-PingOneSeededObject -Type Groups -Connection $script:Connection) | Should-BeCollection -Count 0
            }
        }
    }

    Context 'Platform objects are refused by type' {

        It 'never claims a platform application, even one that carries the tag and prefix' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'applications' } {
                    [PSCustomObject]@{ id = 'console'; name = 'ZZ-TEST-Admin Console'; description = 'ZZ-TEST-seed'; type = 'PING_ONE_ADMIN_CONSOLE' }
                    [PSCustomObject]@{ id = 'ours'; name = 'ZZ-TEST-Expenses'; description = 'ZZ-TEST-seed'; type = 'WEB_APP' }
                }
                @(Get-PingOneSeededObject -Type Applications -Connection $script:Connection).id | Should-BeCollection @('ours')
            }
        }

        It 'never claims a built-in resource, even one that carries the tag and prefix' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'resources' } {
                    [PSCustomObject]@{ id = 'p1api'; name = 'ZZ-TEST-PingOne API'; description = 'ZZ-TEST-seed'; type = 'PINGONE_API' }
                    [PSCustomObject]@{ id = 'ours'; name = 'ZZ-TEST-Orders'; description = 'ZZ-TEST-seed'; type = 'CUSTOM' }
                }
                @(Get-PingOneSeededObject -Type Resources -Connection $script:Connection).id | Should-BeCollection @('ours')
            }
        }
    }

    Context 'Users are proved by population first, then by the tag' {

        It 'claims users in a seeded population, and a tagged user moved out of one, once each' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas' } { [PSCustomObject]@{ id = 's1' } }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas/s1/attributes' } {
                    [PSCustomObject]@{ id = 'a1'; name = 'zzTestSeedTag'; schemaType = 'CUSTOM' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'populations' } {
                    [PSCustomObject]@{ id = 'pop-seeded'; name = 'ZZ-TEST-Staff'; description = 'Staff ZZ-TEST-seed' }
                    [PSCustomObject]@{ id = 'pop-real'; name = 'Sample Users'; description = '' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' -and $Query.filter -like 'population.id eq*' } {
                    [PSCustomObject]@{ id = 'u-in-pop'; username = 'zz-test-ada' }
                    [PSCustomObject]@{ id = 'u-both'; username = 'zz-test-jose' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' -and $Query.filter -like 'zzTestSeedTag eq*' } {
                    [PSCustomObject]@{ id = 'u-both'; username = 'zz-test-jose' }
                    [PSCustomObject]@{ id = 'u-moved'; username = 'zz-test-moved' }
                }

                $ids = @(Get-PingOneSeededObject -Type Users -Connection $script:Connection).id | Sort-Object
                $ids | Should-BeCollection @('u-both', 'u-in-pop', 'u-moved')
            }
        }

        It 'only asks about the seeded populations, never a sample one' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas' } { [PSCustomObject]@{ id = 's1' } }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas/s1/attributes' } { }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'populations' } {
                    [PSCustomObject]@{ id = 'pop-seeded'; name = 'ZZ-TEST-Staff'; description = 'ZZ-TEST-seed' }
                    [PSCustomObject]@{ id = 'pop-real'; name = 'Sample Users'; description = '' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' } { }

                $null = Get-PingOneSeededObject -Type Users -Connection $script:Connection
                Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' -and $Query.filter -like '*pop-real*' }
            }
        }

        It 'never filters by the tag when its attribute does not exist' {
            # Found live. The attribute is absent on a fresh environment and again after teardown
            # removes it last. PingOne refuses a filter naming it with HTTP 400 REQUEST_FAILED,
            # which threw from a report before the first seed and from a second teardown. The
            # schema is asked first, so the refused query is never made.
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas' } { [PSCustomObject]@{ id = 's1' } }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas/s1/attributes' } {
                    [PSCustomObject]@{ id = 'x'; name = 'username'; schemaType = 'CORE' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'populations' } { }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' } { throw 'REQUEST_FAILED on attribute' }

                @(Get-PingOneSeededObject -Type Users -Connection $script:Connection) | Should-BeCollection -Count 0
                Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Path -eq 'users' -and $Query.filter -like 'zzTestSeedTag*' }
            }
        }
    }

    Context 'Attributes are proved by declaration and type' {

        It 'claims only CUSTOM attributes this module declares' {
            InModuleScope TestEnvironment {
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas' } {
                    [PSCustomObject]@{ id = 's1'; name = 'User' }
                }
                Mock Invoke-PingOneRequest -ParameterFilter { $Path -eq 'schemas/s1/attributes' } {
                    [PSCustomObject]@{ id = 'a-ours'; name = 'zzTestSeedTag'; schemaType = 'CUSTOM' }
                    [PSCustomObject]@{ id = 'a-person'; name = 'costCentre'; schemaType = 'CUSTOM' }
                    [PSCustomObject]@{ id = 'a-core'; name = 'labBadgeId'; schemaType = 'CORE' }
                }

                $claimed = @(Get-PingOneSeededObject -Type Attributes -Connection $script:Connection)
                $claimed.id | Should-BeCollection @('a-ours')
                $claimed[0].SchemaId | Should-Be 's1'
            }
        }
    }
}
