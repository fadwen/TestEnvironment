#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Regression tests for the licence check, which is the gate the whole module is shaped
    around.

    The defect these exist for was found by running the module against a real tenant twice.
    The check compared the required slots against Available, which counts every non-deprovisioned
    user including the eight this module had just created. So once a seed succeeded, the
    tenant sat at 10/10 and a second run was refused - even though re-running creates nothing
    new, because New-OktaUser updates an existing login rather than duplicating it.

    That made the module unable to re-run against the environment it had itself built, which
    is precisely the situation you are in when a seed fails halfway and you want to fix the
    cause and try again.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OktaUserHeadroom' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{
                    OrgUrl              = 'https://trial-000000.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                    ActiveUserLimit     = 10
                }
            }
        }
    }

    It 'counts every listed user against the limit' {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                @(1..4 | ForEach-Object {
                    [PSCustomObject]@{ id = "u$_"; profile = [PSCustomObject]@{ login = "real$_@contoso.com" } }
                })
            }

            $headroom = Get-OktaUserHeadroom -ActiveUserLimit 10
            $headroom.InUse | Should-Be 4
            $headroom.Available | Should-Be 6
        }
    }

    It 'treats already-seeded users as reusable rather than as consumed headroom' {
        # The regression. Eight seeded users plus two real ones is a full tenant, but re-seeding
        # those same eight needs no new slot at all.
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                @(
                    @(1..8 | ForEach-Object {
                        [PSCustomObject]@{
                            id      = "s$_"
                            profile = [PSCustomObject]@{
                                login      = "seed$_@oktalab.example.com"
                                labSeedTag = 'OKTALAB-seed'
                            }
                        }
                    })
                    [PSCustomObject]@{ id = 'a1'; profile = [PSCustomObject]@{ login = 'admin@contoso.com' } }
                    [PSCustomObject]@{ id = 'a2'; profile = [PSCustomObject]@{ login = 'other@contoso.com' } }
                )
            }

            $headroom = Get-OktaUserHeadroom -ActiveUserLimit 10

            $headroom.InUse | Should-Be 10
            $headroom.Available | Should-Be 0
            $headroom.SeededInUse | Should-Be 8
            $headroom.AvailableForSeed | Should-Be 8
        }
    }

    It 'does not credit somebody else`s users as reusable' {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                @(
                    [PSCustomObject]@{ id = 'a1'; profile = [PSCustomObject]@{ login = 'admin@contoso.com' } }
                    [PSCustomObject]@{
                        id      = 'o1'
                        profile = [PSCustomObject]@{ login = 'x@otherlab.example.com'; labSeedTag = 'CONTOSO-seed' }
                    }
                )
            }

            $headroom = Get-OktaUserHeadroom -ActiveUserLimit 10
            $headroom.SeededInUse | Should-Be 0
            $headroom.AvailableForSeed | Should-Be 8
        }
    }

    It 'never reports negative headroom on an over-subscribed tenant' {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                @(1..15 | ForEach-Object {
                    [PSCustomObject]@{ id = "u$_"; profile = [PSCustomObject]@{ login = "real$_@contoso.com" } }
                })
            }

            (Get-OktaUserHeadroom -ActiveUserLimit 10).Available | Should-Be 0
        }
    }
}

Describe 'Test-OktaPrerequisite licence gate' -Tag 'Unit', 'Private' {

    It 'permits a re-seed of a tenant that is full of this module`s own users' {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection { @{ OrgUrl = 'https://trial-000000.okta.com' } }
            Mock Get-OktaUserHeadroom {
                [PSCustomObject]@{
                    Limit = 10; InUse = 10; Available = 0; SeededInUse = 8; AvailableForSeed = 8
                }
            }

            Test-OktaPrerequisite -RequiredUserSlots 8 | Should-BeTrue
        }
    }

    It 'still refuses when the tenant is genuinely full of other people`s users' {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection { @{ OrgUrl = 'https://trial-000000.okta.com' } }
            Mock Get-OktaUserHeadroom {
                [PSCustomObject]@{
                    Limit = 10; InUse = 10; Available = 0; SeededInUse = 0; AvailableForSeed = 0
                }
            }

            Test-OktaPrerequisite -RequiredUserSlots 8 -ErrorAction SilentlyContinue | Should-BeFalse
        }
    }
}
