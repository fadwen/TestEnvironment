#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    SecretStore configuration is per USER, not per vault. ADTestEnvironment,
    OktaTestEnvironment and this module all register vaults against the same physical store, so
    anything one of them configures, the others inherit.

    Two facts make that dangerous, and both are pinned here:

    - Get-SecretStoreConfiguration THROWS when the store is locked, and that error is proof a
      password IS configured. Read as a plain failure it looks identical to "never configured",
      and the caller then tries to configure a store that already is one - which
      Set-SecretStoreConfiguration answers with a message about not being able to add a new
      password, describing a different problem entirely.
    - A swallowed unlock failure defers the error to every subsequent read and write, each of
      which then complains about the secret rather than about the password.

    Verified against a live machine where OktaTestEnvironment had configured the store first.
#>

BeforeDiscovery {
    # Pester can only mock a command it can resolve, so the SecretStore cmdlets have to exist in
    # the session before the mocks are defined. They are a real dependency of the vault path and
    # of nothing else, so where they are absent this Describe skips rather than failing - which
    # keeps the suite's promise that it runs on a bare host with no gallery modules.
    $script:HasSecretStore = [bool](Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore)
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force

    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore) {
        Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction SilentlyContinue
        Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TestSecretStoreState' -Tag 'Unit', 'Safety' {

    It 'reports an unconfigured store as unconfigured' {
        InModuleScope TestEnvironment {
            Mock Get-SecretStoreConfiguration { throw 'The SecretStore has not been configured.' }

            $state = Get-TestSecretStoreState
            $state.Configured | Should-BeFalse
        }
    }

    It 'reports a configured store and the authentication it uses' {
        InModuleScope TestEnvironment {
            Mock Get-SecretStoreConfiguration { [PSCustomObject]@{ Authentication = 'None'; Interaction = 'None' } }

            $state = Get-TestSecretStoreState
            $state.Configured | Should-BeTrue
            $state.Authentication | Should-Be 'None'
        }
    }

    It 'treats a LOCKED store as configured, not as absent' {
        InModuleScope TestEnvironment {
            # The regression. This error is what a password-protected store returns when
            # locked, and reading it as "not configured" is what sends the caller into
            # reconfiguring a store another module owns.
            Mock Get-SecretStoreConfiguration {
                throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.'
            }

            $state = Get-TestSecretStoreState
            $state.Configured | Should-BeTrue
            $state.Authentication | Should-Be 'Password'
            $state.Locked | Should-BeTrue
        }
    }
}

Describe 'Initialize-TestSecretVault' -Tag 'Unit', 'Safety' -Skip:(-not $script:HasSecretStore) {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Configured = $false

            # Reported as present so the install branch is never reached. Mocking
            # Install-Module directly is not possible on a host where PowerShellGet is not
            # loaded - Pester cannot mock a command it cannot resolve - and the test would
            # then pass or fail depending on the machine rather than on the code.
            Mock Get-Module { [PSCustomObject]@{ Name = 'stub' } }
            Mock Import-Module { }
            Mock Set-SecretStoreConfiguration { $script:Configured = $true }
            Mock Register-SecretVault { }
            Mock Unlock-SecretStore { }
            Mock Get-SecretVault { $null }
        }
    }

    It 'configures a store that has never been configured' {
        InModuleScope TestEnvironment {
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $false; Authentication = $null; Locked = $false } }

            Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false | Out-Null

            Should-Invoke Set-SecretStoreConfiguration -Times 1
        }
    }

    It 'NEVER reconfigures a store another module already configured' {
        InModuleScope TestEnvironment {
            # The property that keeps three modules from fighting. Reconfiguring re-encrypts a
            # store the others keep credentials in.
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $true; Authentication = 'Password'; Locked = $true } }

            Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false | Out-Null

            Should-NotInvoke Set-SecretStoreConfiguration
        }
    }

    It 'adapts to a passwordless store rather than imposing a password on it' {
        InModuleScope TestEnvironment {
            # ADTestEnvironment prefers Authentication None. Finding that, this module uses it
            # rather than changing it - and must not try to unlock a store with no password.
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $true; Authentication = 'None'; Locked = $false } }

            $result = Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false

            Should-NotInvoke Set-SecretStoreConfiguration
            Should-NotInvoke Unlock-SecretStore
            $result.Available | Should-BeTrue
        }
    }

    It 'fails loudly when the store cannot be unlocked' {
        InModuleScope TestEnvironment {
            # Swallowing this defers the error to every read and write that follows, each of
            # which then reports a missing secret rather than a wrong password.
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $true; Authentication = 'Password'; Locked = $true } }
            Mock Unlock-SecretStore { throw 'Store file integrity check failed.' }

            { Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*VaultPassword*'
        }
    }

    It 'names the other modules in that failure, because they are the likely cause' {
        InModuleScope TestEnvironment {
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $true; Authentication = 'Password'; Locked = $true } }
            Mock Unlock-SecretStore { throw 'Store file integrity check failed.' }

            { Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*per-user store*'
        }
    }

    It 'registers the vault only when it does not already exist' {
        InModuleScope TestEnvironment {
            Mock Get-TestSecretStoreState { [PSCustomObject]@{ Configured = $true; Authentication = 'None'; Locked = $false } }
            Mock Get-SecretVault { [PSCustomObject]@{ Name = 'Test' } }

            $result = Initialize-TestSecretVault -VaultName 'Test' -Install -Confirm:$false

            Should-NotInvoke Register-SecretVault
            $result.Created | Should-BeFalse
            $result.Available | Should-BeTrue
        }
    }
}
