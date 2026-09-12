#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Tests for the helper that works out which parts of an account name its password may not
    contain.

    The rule is Windows', not this module's: password complexity refuses any password holding
    the account's sAMAccountName, or a token of its display name three characters or longer,
    compared case-insensitively and split on , . - _ space tab and #. Active Directory reports
    the refusal as "the password does not meet the length, complexity, or history requirement
    of the domain", naming none of the three, which is why it went unexplained for so long.

    Every case below was confirmed against a live domain controller before being written here.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ADTestNameToken' -Tag 'Unit', 'Private' {

    Context 'What the directory actually checks' {

        It 'splits the display name into its words' {
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'ZZ-TEST-Web Application Service' -SamAccountName 'svc-webapp'
                $tokens | Should-ContainCollection 'Web'
                $tokens | Should-ContainCollection 'Application'
                $tokens | Should-ContainCollection 'Service'
            }
        }

        It 'includes TEST, which the seed prefix puts on every account it creates' {
            # Confirmed live: a password containing TEST is refused on a seeded account.
            # This is the token that makes the rule apply to all twenty-five of them rather
            # than to the handful with a short word of their own.
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'ZZ-TEST-Backup Service Account' -SamAccountName 'svc-backup'
                $tokens | Should-ContainCollection 'TEST'
            }
        }

        It 'drops tokens shorter than three characters' {
            # ZZ is two characters, so the directory ignores it. Treating it as forbidden
            # would throw away candidates for nothing.
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'ZZ-TEST-Web Application Service' -SamAccountName 'svc-webapp'
                $tokens | Should-NotContainCollection 'ZZ'
            }
        }

        It 'keeps the logon name whole rather than splitting it' {
            # The sAMAccountName is checked entire, so svc-webapp is the token, not svc.
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'ZZ-TEST-Web Application Service' -SamAccountName 'svc-webapp'
                $tokens | Should-ContainCollection 'svc-webapp'
                $tokens | Should-NotContainCollection 'svc'
            }
        }

        It 'splits on every delimiter the directory splits on' {
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'alpha,bravo.charlie-delta_echo foxtrot#golf' -SamAccountName ''
                foreach ($word in 'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf') {
                    $tokens | Should-ContainCollection $word
                }
            }
        }

        It 'treats tokens case-insensitively rather than returning near-duplicates' {
            # The comparison the directory makes ignores case, so holding both spellings
            # would only cost extra draws.
            InModuleScope TestEnvironment {
                $tokens = Get-ADTestNameToken -DisplayName 'Test TEST test' -SamAccountName ''
                @($tokens).Count | Should-Be 1
            }
        }
    }

    Context 'Names that yield nothing' {

        It 'returns an empty collection for an empty name' {
            InModuleScope TestEnvironment {
                @(Get-ADTestNameToken -DisplayName '' -SamAccountName '') | Should-BeCollection -Count 0
            }
        }

        It 'returns an empty collection when nothing is long enough' {
            InModuleScope TestEnvironment {
                @(Get-ADTestNameToken -DisplayName 'a b-c' -SamAccountName 'ab') | Should-BeCollection -Count 0
            }
        }

        It 'returns nothing for a null name rather than failing' {
            InModuleScope TestEnvironment {
                @(Get-ADTestNameToken -DisplayName $null -SamAccountName $null) |
                    Should-BeCollection -Count 0
            }
        }
    }

    Context 'Every seeded service account is covered' {

        It 'produces at least one forbidden token for every row in the seed data' {
            # If any account produced none, its password would be unconstrained and the
            # original defect would still be reachable through that row.
            InModuleScope TestEnvironment {
                $accounts = Import-Csv -LiteralPath (Join-Path (Get-ADTestDataPath) 'ADServiceAccounts.csv') -Encoding UTF8
                $prefix = (Get-ADTestSeedMarker).Prefix

                $bare = foreach ($account in $accounts) {
                    $tokens = Get-ADTestNameToken -DisplayName ($prefix + $account.Name) `
                        -SamAccountName $account.SamAccountName
                    if (@($tokens).Count -eq 0) { $account.SamAccountName }
                }

                @($bare) | Should-BeCollection -Count 0
            }
        }
    }
}
