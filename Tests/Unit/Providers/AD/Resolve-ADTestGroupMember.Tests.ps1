#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one place the membership rules in ADSecurityGroups.csv are interpreted.

    The rules used to be a regex switch on group names inside a background job, where no mock
    could reach them and every search ran across the whole domain. What is pinned here is the
    contract the rows now rely on: the filter goes to the directory as written and scoped to the
    seed OU, a device-owner rule keeps only owners inside the seed OU, a person matched twice is
    returned once, and a limit picks the same people every run.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-ADTestGroupMember' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Root = 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
            $script:User = {
                param($sam)
                [PSCustomObject]@{ SamAccountName = $sam; DistinguishedName = "CN=$sam,OU=Users,$($script:Root)" }
            }
            Mock Get-ADUser { @((& $script:User 'bmoore'), (& $script:User 'alopez'), (& $script:User 'alopez')) }
            Mock Get-ADComputer { @() }
        }
    }

    It 'sends the filter to the directory as written, scoped to the seed OU' {
        InModuleScope TestEnvironment {
            $rule = [PSCustomObject]@{ GroupName = 'Sales'; MemberFilter = "Department -eq 'Sales'"; MemberSource = ''; MemberLimit = '' }

            $null = Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root

            Should-Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter {
                $Filter -eq "Department -eq 'Sales'" -and $SearchBase -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
            }
        }
    }

    It 'returns a person matched twice once' {
        InModuleScope TestEnvironment {
            $rule = [PSCustomObject]@{ GroupName = 'Sales'; MemberFilter = "Department -eq 'Sales'"; MemberSource = ''; MemberLimit = '' }

            $members = @(Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root)

            @($members.SamAccountName | Sort-Object) | Should-BeCollection @('alopez', 'bmoore')
        }
    }

    It 'takes the first so many by account name when the row sets a limit, so the same people are chosen every run' {
        InModuleScope TestEnvironment {
            Mock Get-ADUser { @((& $script:User 'zwhite'), (& $script:User 'mbell'), (& $script:User 'alopez'), (& $script:User 'kim')) }
            $rule = [PSCustomObject]@{ GroupName = 'Test Domain Admins'; MemberFilter = "Title -like '*IT*'"; MemberSource = ''; MemberLimit = '2' }

            @((Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root).SamAccountName) | Should-BeCollection @('alopez', 'kim')
        }
    }

    It 'returns nothing, and asks the directory nothing, for a row with no rule' {
        InModuleScope TestEnvironment {
            $rule = [PSCustomObject]@{ GroupName = 'Zürich Site Access'; MemberFilter = ''; MemberSource = ''; MemberLimit = '' }

            @(Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root) | Should-BeCollection -Count 0
            Should-NotInvoke Get-ADUser
        }
    }

    Context 'Device owners' {

        It 'filters the seeded computers and returns their owners, dropping an owner outside the seed OU' {
            # -Identity cannot take -SearchBase, so the owner's distinguished name is the check.
            # Without it a device managed by a real account puts that account in a seeded group.
            InModuleScope TestEnvironment {
                Mock Get-ADComputer {
                    @(
                        [PSCustomObject]@{ Name = 'ZZ-TEST-MOBILE-001'; ManagedBy = "CN=bmoore,OU=Users,$($script:Root)" }
                        [PSCustomObject]@{ Name = 'ZZ-TEST-MOBILE-002'; ManagedBy = "CN=bmoore,OU=Users,$($script:Root)" }
                        [PSCustomObject]@{ Name = 'ZZ-TEST-MOBILE-003'; ManagedBy = 'CN=Administrator,CN=Users,DC=contoso,DC=com' }
                        [PSCustomObject]@{ Name = 'ZZ-TEST-MOBILE-004'; ManagedBy = $null }
                    )
                }
                Mock Get-ADUser {
                    $sam = ($Identity -split ',')[0] -replace '^CN=', ''
                    [PSCustomObject]@{ SamAccountName = $sam; DistinguishedName = $Identity }
                }
                $rule = [PSCustomObject]@{ GroupName = 'Mobile Device Users'; MemberFilter = "Name -like '*Mobile*'"; MemberSource = 'DeviceOwner'; MemberLimit = '' }

                $members = @(Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root)

                @($members.SamAccountName) | Should-BeCollection @('bmoore')
                Should-Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter {
                    $Filter -eq "Name -like '*Mobile*'" -and $SearchBase -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
                }
                Should-NotInvoke Get-ADUser -ParameterFilter { $Identity -like 'CN=Administrator,*' }
            }
        }
    }

    It 'refuses a source it does not know rather than guessing' {
        InModuleScope TestEnvironment {
            $rule = [PSCustomObject]@{ GroupName = 'Odd'; MemberFilter = "Enabled -eq 'True'"; MemberSource = 'Everyone'; MemberLimit = '' }
            { Resolve-ADTestGroupMember -Rule $rule -SeedRoot $script:Root } | Should-Throw -ExceptionMessage '*unknown MemberSource*'
        }
    }
}
