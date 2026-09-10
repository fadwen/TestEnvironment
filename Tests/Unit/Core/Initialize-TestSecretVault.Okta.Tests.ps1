#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    SecretStore configuration is per USER, not per vault. ADTestEnvironment,
    EntraTestEnvironment and this module all register vaults against the same physical store,
    so anything one of them configures, the others inherit - and reconfiguring it re-encrypts
    the store the others keep credentials in.

    Two facts make that dangerous, and both are pinned here. Both were found against a real
    machine where this module had configured the store and EntraTestEnvironment then failed on
    it:

    - Get-SecretStoreConfiguration THROWS when the store is locked, and that error is itself
      proof a password IS configured. Read as a plain failure it is indistinguishable from
      "never configured", and Set-SecretStoreConfiguration then answers with a message about
      not being able to add a new password - which describes a different problem entirely.
    - A swallowed unlock failure defers the error to every subsequent read and write, each of
      which then complains about the secret rather than about the password.
#>

BeforeDiscovery {
    # Pester can only mock a command it can resolve, so the SecretStore cmdlets have to exist
    # in the session before the mocks are defined. They are a real dependency of the vault path
    # and of nothing else, so where they are absent this file skips rather than failing - which
    # keeps the suite's promise that it runs on a bare host with no gallery modules.
    $script:HasSecretStore = [bool](Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore)
}

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force

    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore) {
        Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction SilentlyContinue
        Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Initialize-TestSecretVault' -Tag 'Unit', 'Safety' -Skip:(-not $script:HasSecretStore) {

    BeforeEach {
        InModuleScope TestEnvironment {
            # Reported as present so the gallery-install branch is never reached. Mocking
            # Install-Module directly is not possible on a host where PowerShellGet is not
            # loaded, and the test would then depend on the machine rather than the code.
            Mock Get-Module { [PSCustomObject]@{ Name = 'stub' } }
            Mock Import-Module { }
            Mock Set-SecretStoreConfiguration { }
            Mock Register-SecretVault { }
            Mock Unlock-SecretStore { }
            Mock Get-SecretVault { $null }
            Mock Get-SecretStoreConfiguration { [PSCustomObject]@{ Authentication = 'Password'; Interaction = 'None' } }
        }
    }

    It 'configures a store that has never been configured' {
        InModuleScope TestEnvironment {
            Mock Get-SecretStoreConfiguration { throw 'The SecretStore has not been configured.' }

            Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false | Out-Null

            Should-Invoke Set-SecretStoreConfiguration -Times 1
        }
    }

    It 'NEVER reconfigures a store another module already configured' {
        InModuleScope TestEnvironment {
            Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false | Out-Null

            Should-NotInvoke Set-SecretStoreConfiguration
        }
    }

    It 'treats a LOCKED store as configured, not as absent' {
        InModuleScope TestEnvironment {
            # The regression. Previously this error routed into Set-SecretStoreConfiguration,
            # which failed with a message about a completely different problem.
            Mock Get-SecretStoreConfiguration {
                throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.'
            }

            Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false | Out-Null

            Should-NotInvoke Set-SecretStoreConfiguration
            Should-Invoke Unlock-SecretStore -Times 1
        }
    }

    It 'adapts to a passwordless store rather than imposing a password on it' {
        InModuleScope TestEnvironment {
            # ADTestEnvironment prefers Authentication None. Finding that, this module uses it
            # rather than changing it, and must not try to unlock a store with no password.
            Mock Get-SecretStoreConfiguration { [PSCustomObject]@{ Authentication = 'None'; Interaction = 'None' } }

            $result = Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false

            Should-NotInvoke Set-SecretStoreConfiguration
            Should-NotInvoke Unlock-SecretStore
            $result.Available | Should-BeTrue
        }
    }

    It 'fails loudly when the store cannot be unlocked' {
        InModuleScope TestEnvironment {
            Mock Unlock-SecretStore { throw 'Store file integrity check failed.' }

            { Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false } |
                Should-Throw -ExceptionMessage '*VaultPassword*'
        }
    }

    It 'names the other modules in that failure, because they are the likely cause' {
        InModuleScope TestEnvironment {
            Mock Unlock-SecretStore { throw 'Store file integrity check failed.' }

            { Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false } |
                Should-Throw -ExceptionMessage '*per-user store*'
        }
    }

    It 'registers the vault only when it does not already exist' {
        InModuleScope TestEnvironment {
            Mock Get-SecretVault { [PSCustomObject]@{ Name = 'Test' } }

            $result = Initialize-TestSecretVault -VaultName 'Test' -Confirm:$false

            Should-NotInvoke Register-SecretVault
            $result.Created | Should-BeFalse
            $result.Available | Should-BeTrue
        }
    }
}
