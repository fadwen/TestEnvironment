#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Regression tests for the secret cleanup defect.

    Remove-ADTestSecretVault counted the secrets in a vault, reported that number as
    SecretsRemoved, and then called only Unregister-SecretVault - which removes the vault
    REGISTRATION and leaves every secret in the SecretStore backing store. A comment on the
    line even claimed "this also removes all secrets". Teardown reported success and cleaned
    nothing, and the leftovers accumulated silently across every run.

    The fix has a sharp edge that these tests pin down. SecretStore is a single store per
    user: every registered vault name enumerates the SAME secrets. Deleting everything a
    vault can see would destroy secrets belonging to other vaults and other tools, so the
    removal is filtered on the Source metadata that Set-ADTestPasswordSecret stamps.
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

Describe 'Remove-ADTestSecretVault' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            # Two secrets this module created and one it did not. Only the first two may go.
            $script:MockSecrets = @(
                [PSCustomObject]@{
                    Name = 'svc-a-20260101-000000'; VaultName = 'V'; Metadata = @{ Source = 'ADTestEnvironment' }
                }
                [PSCustomObject]@{
                    Name = 'svc-b-20260101-000000'; VaultName = 'V'; Metadata = @{ Source = 'ADTestEnvironment' }
                }
                [PSCustomObject]@{
                    Name = 'SomeoneElsesSecret';    VaultName = 'V'; Metadata = @{ Source = 'AnotherTool' }
                }
            )

            Mock Get-SecretVault {
                [PSCustomObject]@{ Name = 'V'; ModuleName = 'Microsoft.PowerShell.SecretStore' }
            }
            Mock Get-SecretInfo { $script:MockSecrets }
            Mock Remove-Secret { }
            Mock Unregister-SecretVault { }
            Mock Get-SecretStoreConfiguration { $null }
        }
    }

    Context 'Secrets are actually deleted' {

        It 'calls Remove-Secret rather than relying on Unregister-SecretVault' {
            InModuleScope TestEnvironment {
                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-Invoke Remove-Secret -Times 2 -Exactly
            }
        }

        It 'still unregisters the vault afterwards' {
            InModuleScope TestEnvironment {
                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-Invoke Unregister-SecretVault -Times 1 -Exactly
            }
        }

        It 'reports the number actually removed, not the number found' {
            InModuleScope TestEnvironment {
                $result = Remove-ADTestSecretVault -VaultName 'V' -Force
                $result.SecretsRemoved | Should-Be 2
            }
        }
    }

    Context 'Other tools are not collateral damage' {

        It 'removes only secrets carrying this module Source tag' {
            InModuleScope TestEnvironment {
                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-NotInvoke Remove-Secret -ParameterFilter { $Name -eq 'SomeoneElsesSecret' }
            }
        }

        It 'removes both of its own' {
            InModuleScope TestEnvironment {
                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-Invoke Remove-Secret -ParameterFilter {
                    $Name -eq 'svc-a-20260101-000000'
                } -Times 1 -Exactly
                Should-Invoke Remove-Secret -ParameterFilter {
                    $Name -eq 'svc-b-20260101-000000'
                } -Times 1 -Exactly
            }
        }

        It 'removes nothing when no secret carries the tag' {
            InModuleScope TestEnvironment {
                Mock Get-SecretInfo {
                    @([PSCustomObject]@{
                        Name = 'Foreign'; VaultName = 'V'
                        Metadata = @{ Source = 'AnotherTool' }
                    })
                }

                $result = Remove-ADTestSecretVault -VaultName 'V' -Force

                Should-NotInvoke Remove-Secret
                $result.SecretsRemoved | Should-Be 0
            }
        }

        It 'ignores secrets with no metadata at all' {
            InModuleScope TestEnvironment {
                Mock Get-SecretInfo {
                    @([PSCustomObject]@{ Name = 'Untagged'; VaultName = 'V'; Metadata = $null })
                }

                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-NotInvoke Remove-Secret
            }
        }
    }

    Context 'Force still enumerates' {

        It 'cleans up under -Force, which is the unattended teardown path' {
            # Enumeration used to be skipped under -Force to avoid a password prompt, so the
            # path teardown actually uses never removed anything.
            InModuleScope TestEnvironment {
                $null = Remove-ADTestSecretVault -VaultName 'V' -Force
                Should-Invoke Get-SecretInfo -Times 1 -Exactly
            }
        }
    }

    Context 'A locked store' {

        It 'records an error and still unregisters rather than throwing' {
            InModuleScope TestEnvironment {
                Mock Get-SecretInfo {
                    throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.'
                }

                $result = Remove-ADTestSecretVault -VaultName 'V' -Force

                $result.SecretsRemoved | Should-Be 0
                @($result.Errors).Count | Should-BeGreaterThan 0
                Should-Invoke Unregister-SecretVault -Times 1 -Exactly
            }
        }
    }

    Context 'A vault that does not exist' {

        It 'reports it and removes nothing' {
            InModuleScope TestEnvironment {
                Mock Get-SecretVault { $null }

                $result = Remove-ADTestSecretVault -VaultName 'Missing' -Force

                $result.VaultExists | Should-BeFalse
                Should-NotInvoke Remove-Secret
            }
        }
    }

    # -GlobalVault was declared, documented with its own example, and threaded down from
    # Remove-ADEnvironment, but never read. These pin it to actually being consulted:
    # the switch is meaningless again the moment nothing asserts on it.
    Context 'GlobalVault is honoured rather than merely declared' {

        It 'warns when a global vault is removed without elevation' {
            InModuleScope TestEnvironment {
                Mock Test-ADTestAdministrator { $false }

                $removeArgs = @{
                    VaultName     = 'V'
                    Force         = $true
                    GlobalVault   = $true
                    WarningAction = 'SilentlyContinue'
                }
                $result = Remove-ADTestSecretVault @removeArgs

                @($result.Warnings) -join ' ' | Should-MatchString 'not running as administrator'
            }
        }

        It 'does not warn when elevated' {
            InModuleScope TestEnvironment {
                Mock Test-ADTestAdministrator { $true }

                $result = Remove-ADTestSecretVault -VaultName 'V' -Force -GlobalVault

                @($result.Warnings) -join ' ' | Should-NotMatchString 'not running as administrator'
            }
        }

        It 'does not consult elevation at all without the switch' {
            InModuleScope TestEnvironment {
                Mock Test-ADTestAdministrator { $true }

                $null = Remove-ADTestSecretVault -VaultName 'V' -Force

                Should-NotInvoke Test-ADTestAdministrator
            }
        }
    }
}
