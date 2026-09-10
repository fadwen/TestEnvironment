function Get-TestSecretStoreState {
    <#
    .SYNOPSIS
        Reports whether SecretStore is configured, and how, without changing it

    .DESCRIPTION
        Answering "is this store already set up" is harder than it looks, and getting it wrong
        is what makes three modules fight over one store.

        SecretStore configuration is per USER, not per vault. ADTestEnvironment,
        OktaTestEnvironment and this module all register vaults against the same physical
        store, so whatever one of them configures, the others inherit. Reconfiguring it is
        therefore never a local decision.

        The trap is that Get-SecretStoreConfiguration THROWS when the store is locked, with
        "A valid password is required to access the Microsoft.PowerShell.SecretStore vault".
        That error is itself proof a password is configured - but read as a plain failure it
        looks identical to "never configured", and the caller then tries to configure a store
        that already is one. Set-SecretStoreConfiguration answers that with a message about not
        being able to add a new password, which describes a different problem entirely and
        sends you looking in the wrong place.

    .OUTPUTS
        TestSecretStoreState with Configured, Authentication and Locked.

    .EXAMPLE
        PS> Get-TestSecretStoreState

        DESCRIPTION: Reports the shared store's current state
        OUTPUT: Configured=True Authentication=Password Locked=True
        USE CASE: Called by Initialize-TestSecretVault before it decides whether to configure

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('TestSecretStoreState')]
    param()

    $state = [PSCustomObject]@{
        PSTypeName     = 'TestSecretStoreState'
        Configured     = $false
        Authentication = $null
        Locked         = $false
    }

    try {
        $configuration = Get-SecretStoreConfiguration -ErrorAction Stop
        $state.Configured = $true
        $state.Authentication = [string]$configuration.Authentication
    }
    catch {
        if ($_.Exception.Message -match 'valid password is required') {
            # Locked, which can only be true of a store that has a password.
            $state.Configured = $true
            $state.Authentication = 'Password'
            $state.Locked = $true
            Write-Verbose 'SecretStore is configured with a password and is currently locked'
        }
        else {
            Write-Verbose "SecretStore has no configuration yet: $($_.Exception.Message)"
        }
    }

    return $state
}
