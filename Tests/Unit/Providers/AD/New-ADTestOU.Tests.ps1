#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    New-ADTestOU gained an -Unprotected switch and a DistinguishedName in its return value.
    Both are load-bearing:

    - accidental-deletion protection is ON by default in New-ADOrganizationalUnit, and a
      protected child blocks the recursive delete the edge case teardown depends on
    - the default must stay protected, because the main OU tree relies on it

    Every AD call is mocked. These are unit tests; nothing here touches a directory.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-ADTestOU' -Tag 'Unit', 'Private' {

    Context 'Creating an OU that does not exist' {

        It 'reports Created and returns the distinguished name' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }
                Mock New-ADOrganizationalUnit { }

                $result = New-ADTestOU -Name 'Widgets' -Path 'OU=Test,DC=contoso,DC=com' -Description 'd'

                $result.Action | Should-Be 'Created'
                $result.Success | Should-BeTrue
                $result.DistinguishedName | Should-Be 'OU=Widgets,OU=Test,DC=contoso,DC=com'
            }
        }

        It 'leaves accidental-deletion protection alone by default' {
            # The main OU tree depends on staying protected. Passing the parameter at all
            # would be a regression, so the assertion is that it is absent.
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }
                Mock New-ADOrganizationalUnit { }

                $null = New-ADTestOU -Name 'Widgets' -Path 'OU=Test,DC=contoso,DC=com' -Description 'd'

                Should-Invoke New-ADOrganizationalUnit -Times 1 -Exactly -ParameterFilter {
                    -not $PSBoundParameters.ContainsKey('ProtectedFromAccidentalDeletion')
                }
            }
        }

        It 'disables protection when -Unprotected is passed' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }
                Mock New-ADOrganizationalUnit { }

                $ouArgs = @{
                    Name        = 'EdgeCases'
                    Path        = 'OU=Test,DC=contoso,DC=com'
                    Description = 'd'
                    Unprotected = $true
                }
                $null = New-ADTestOU @ouArgs

                Should-Invoke New-ADOrganizationalUnit -Times 1 -Exactly -ParameterFilter {
                    $ProtectedFromAccidentalDeletion -eq $false
                }
            }
        }
    }

    Context 'Creating an OU that already exists' {

        It 'reports Skipped and creates nothing' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit {
                    [PSCustomObject]@{ DistinguishedName = 'OU=Widgets,OU=Test,DC=contoso,DC=com' }
                }
                Mock New-ADOrganizationalUnit { }

                $result = New-ADTestOU -Name 'Widgets' -Path 'OU=Test,DC=contoso,DC=com' -Description 'd'

                $result.Action | Should-Be 'Skipped'
                Should-NotInvoke New-ADOrganizationalUnit
            }
        }

        It 'still returns the distinguished name, so callers need not rebuild it' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit {
                    [PSCustomObject]@{ DistinguishedName = 'OU=Widgets,OU=Test,DC=contoso,DC=com' }
                }
                Mock New-ADOrganizationalUnit { }

                $result = New-ADTestOU -Name 'Widgets' -Path 'OU=Test,DC=contoso,DC=com' -Description 'd'
                $result.DistinguishedName | Should-Be 'OU=Widgets,OU=Test,DC=contoso,DC=com'
            }
        }
    }

    Context 'WhatIf' {

        It 'creates nothing and reports WhatIf' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }
                Mock New-ADOrganizationalUnit { }

                $result = New-ADTestOU -Name 'Widgets' -Path 'OU=Test,DC=contoso,DC=com' -Description 'd' -WhatIf

                $result.Action | Should-Be 'WhatIf'
                Should-NotInvoke New-ADOrganizationalUnit
            }
        }
    }

    Context 'Failure handling' {

        It 'reports Failed rather than throwing when the directory rejects the create' {
            InModuleScope TestEnvironment {
                Mock Get-ADOrganizationalUnit { $null }
                Mock New-ADOrganizationalUnit { throw 'Access is denied' }

                $newADTestOUArgs1 = @{
                    Name        = 'Widgets'
                    Path        = 'OU=Test,DC=contoso,DC=com'
                    Description = 'd'
                    ErrorAction = 'SilentlyContinue'
                }
                $result = New-ADTestOU @newADTestOUArgs1

                $result.Success | Should-BeFalse
                $result.Action | Should-Be 'Failed'
            }
        }
    }
}
