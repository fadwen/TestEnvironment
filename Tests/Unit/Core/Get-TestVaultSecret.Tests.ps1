#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Get-TestVaultSecret is the read side of the SecretStore path: what Connect-TestEnvironment
    -UseSecretStore runs to get the service app's private key back. The store it reads is per
    USER and shared with everything that has ever configured it, and the three earlier modules
    each configured it with their own default password.

    Initialize-TestSecretVault has always tried each of those defaults in turn. This function
    tried only the current one, so on a machine whose store had been set up by
    OktaTestEnvironment the stored-credential connect failed with an instruction to unlock a
    store the caller had never been asked for a password to. Found against a real tenant
    teardown on 2026-09-09; the fix and this suite arrived together.
#>

# The passwords below are the module's own published defaults and one made-up string, typed
# into a test to prove which of them the helper offers the store and in what order. None is a
# credential.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Published lab defaults and a placeholder, used to assert the unlock order.')]
param()

BeforeDiscovery {
    # Pester can only mock a command it can resolve, so the SecretStore cmdlets have to exist
    # in the session before the mocks are defined. Where they are absent this file skips rather
    # than failing, which keeps the suite's promise that it runs on a bare host.
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

Describe 'Get-TestVaultSecret' -Tag 'Unit', 'Safety' -Skip:(-not $script:HasSecretStore) {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-Module { [PSCustomObject]@{ Name = 'stub' } }
            Mock Import-Module { }
            Mock Get-Secret { 'c2VjcmV0' }

            # Records every password offered, in order, and opens only for the one named by
            # $script:Opens. Marshalled back to plain text the same way the module does it.
            $script:Attempts = [System.Collections.Generic.List[string]]::new()
            $script:Opens = 'OktaTestEnvironmentPassword'
            Mock Unlock-SecretStore {
                $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                try { $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
                finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
                $script:Attempts.Add($plain)
                if ($plain -ne $script:Opens) { throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.' }
            }
        }
    }

    It 'opens a store configured by an earlier module, trying the current default first' {
        InModuleScope TestEnvironment {
            $result = Get-TestVaultSecret -VaultName 'EntraEnvironment' -SecretName 'key'

            $result | Should-Be 'c2VjcmV0'
            $script:Attempts | Should-BeCollection @('TestEnvironmentPassword', 'OktaTestEnvironmentPassword')
        }
    }

    It 'tries every published default before giving up' {
        InModuleScope TestEnvironment {
            $script:Opens = 'none-of-them'
            Mock Get-Secret { throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.' }

            { Get-TestVaultSecret -VaultName 'EntraEnvironment' -SecretName 'key' } |
                Should-Throw -ExceptionMessage '*Unlock-SecretStore*'

            $script:Attempts | Should-BeCollection @(
                'TestEnvironmentPassword', 'OktaTestEnvironmentPassword',
                'ADTestEnvironmentPassword', 'EntraTestEnvironmentPassword'
            )
        }
    }

    It 'offers only the caller''s password when one is supplied' {
        # The defaults are a fallback for the unattended case, never an override of an
        # explicit choice: a caller who names a password that does not open the store must
        # hear that, not have the store quietly opened with something else.
        InModuleScope TestEnvironment {
            $script:Opens = 'none-of-them'
            Mock Get-Secret { throw 'A valid password is required to access the Microsoft.PowerShell.SecretStore vault.' }
            $own = ConvertTo-SecureString -String 'MyOwnPassword' -AsPlainText -Force

            { Get-TestVaultSecret -VaultName 'EntraEnvironment' -SecretName 'key' -VaultPassword $own } |
                Should-Throw

            $script:Attempts | Should-BeCollection @('MyOwnPassword')
        }
    }

    It 'stops at the first password that opens the store' {
        InModuleScope TestEnvironment {
            $script:Opens = 'TestEnvironmentPassword'

            Get-TestVaultSecret -VaultName 'EntraEnvironment' -SecretName 'key' | Out-Null

            $script:Attempts | Should-BeCollection @('TestEnvironmentPassword')
        }
    }
}
