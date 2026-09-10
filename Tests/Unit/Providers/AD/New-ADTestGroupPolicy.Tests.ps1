#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Tests for the companion deny-logon Group Policy.

    The things worth pinning down here are all about blast radius rather than mechanics.
    A GPO is a domain object that lives outside OU=TestData, and deleting one is not
    recoverable, so these assert that the policy is scoped to the test devices, that it is
    marked as test data, and that a teardown will not touch a policy this module did not
    create.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT, SecretManagement and GPMC are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-ADTestGroupPolicy' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
            Mock Import-Module { }
            Mock Get-ADOrganizationalUnit {
                [PSCustomObject]@{ DistinguishedName = 'OU=Devices,OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            }
            Mock Get-ADUser {
                @(
                    [PSCustomObject]@{
                        SamAccountName = 'svc-a'
                        SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1-1-1-1001' }
                    }
                    [PSCustomObject]@{
                        SamAccountName = 'svc-b'
                        SID            = [PSCustomObject]@{ Value = 'S-1-5-21-1-1-1-1002' }
                    }
                )
            }
            Mock Get-GPO { $null }
            Mock New-GPO { [PSCustomObject]@{ Id = [guid]'11111111-2222-3333-4444-555555555555' } }
            Mock Get-GPInheritance { [PSCustomObject]@{ GpoLinks = @() } }
            Mock New-GPLink { }
            Mock Set-ADTestPolicyUserRight { }
        }
    }

    Context 'Scope is limited to the test data' {

        It 'links to the test Devices OU and nowhere else' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy

                Should-Invoke New-GPLink -Times 1 -Exactly
                Should-Invoke New-GPLink -ParameterFilter {
                    $Target -eq 'OU=Devices,OU=ZZ-TEST-TestData,DC=contoso,DC=com'
                } -Times 1 -Exactly
            }
        }

        It 'never links at the domain root' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy
                Should-NotInvoke New-GPLink -ParameterFilter { $Target -eq 'DC=contoso,DC=com' }
            }
        }

        It 'names only accounts from the test ServiceAccounts OU' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy
                Should-Invoke Get-ADUser -ParameterFilter {
                    $SearchBase -eq 'OU=ServiceAccounts,OU=ZZ-TEST-TestData,DC=contoso,DC=com'
                } -Times 1 -Exactly
            }
        }
    }

    Context 'The policy is identifiable as test data' {

        It 'creates it with the test name' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy
                Should-Invoke New-GPO -ParameterFilter {
                    $Name -eq 'ZZ-TEST-Deny Service Account Logon'
                } -Times 1 -Exactly
            }
        }

        It 'stamps the marker into the comment, which teardown matches on' {
            InModuleScope TestEnvironment {
                $marker = (Get-ADTestPolicySetting -DomainDN 'DC=contoso,DC=com').Marker
                $null = New-ADTestGroupPolicy
                Should-Invoke New-GPO -ParameterFilter { $Comment -like "*$marker*" } -Times 1 -Exactly
            }
        }
    }

    Context 'Rights that are actually assigned' {

        It 'writes all three deny-logon rights' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy
                Should-Invoke Set-ADTestPolicyUserRight -ParameterFilter {
                    $Right -contains 'SeDenyInteractiveLogonRight' -and
                    $Right -contains 'SeDenyRemoteInteractiveLogonRight' -and
                    $Right -contains 'SeDenyNetworkLogonRight'
                } -Times 1 -Exactly
            }
        }

        It 'reports how many accounts were named' {
            InModuleScope TestEnvironment {
                $result = New-ADTestGroupPolicy -PassThru
                $result.AccountCount | Should-Be 2
            }
        }
    }

    Context 'Preconditions' {

        It 'does nothing when the link target OU is missing' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }

                $result = New-ADTestGroupPolicy -PassThru -WarningAction SilentlyContinue

                Should-NotInvoke New-GPO
                $result.Created | Should-BeFalse
            }
        }

        It 'does nothing when there are no service accounts to name' {
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }

                $result = New-ADTestGroupPolicy -PassThru -WarningAction SilentlyContinue

                Should-NotInvoke New-GPO
                Should-NotInvoke Set-ADTestPolicyUserRight
                $result.Created | Should-BeFalse
            }
        }

        It 'reuses an existing policy rather than creating a second one' {
            InModuleScope TestEnvironment {
                Mock Get-GPO { [PSCustomObject]@{ Id = [guid]'99999999-9999-9999-9999-999999999999' } }

                $null = New-ADTestGroupPolicy

                Should-NotInvoke New-GPO
                Should-Invoke Set-ADTestPolicyUserRight -Times 1 -Exactly
            }
        }

        It 'does not create the policy under -WhatIf' {
            InModuleScope TestEnvironment {
                $null = New-ADTestGroupPolicy -WhatIf

                Should-NotInvoke New-GPO
                Should-NotInvoke New-GPLink
                Should-NotInvoke Set-ADTestPolicyUserRight
            }
        }
    }
}
