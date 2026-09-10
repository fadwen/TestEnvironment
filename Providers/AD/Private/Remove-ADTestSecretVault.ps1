function Remove-ADTestSecretVault {
    <#
    .SYNOPSIS
        Removes a SecretStore vault created for AD test environment

    .DESCRIPTION
        Safely removes a SecretStore vault and all its stored secrets.
        Includes safety checks and error handling.

    .PARAMETER VaultName
        Name of the secret vault to remove. Defaults to "ADTestEnvironment"

    .PARAMETER Force
        Force removal without additional confirmation

    .PARAMETER ResetSecretStore
        Also reset the global SecretStore configuration to defaults.
        When used with -Force, sets SecretStore to no authentication mode.
        Without -Force, uses interactive Reset-SecretStore (prompts for new password).
        WARNING: This will affect ALL SecretStore vaults on the system.
        Use with caution if you have other vaults configured.

    .PARAMETER GlobalVault
        The vault was created at AllUsers scope instead of CurrentUser scope.
        This parameter helps ensure proper vault removal.

    .EXAMPLE
        Remove-ADTestSecretVault
        Removes the default ADTestEnvironment vault

    .EXAMPLE
        Remove-ADTestSecretVault -ResetSecretStore
        Removes the default vault AND resets SecretStore configuration

    .EXAMPLE
        Remove-ADTestSecretVault -VaultName "ProdVault" -ResetSecretStore -Force
        Removes a custom vault, resets SecretStore, without prompts

    .EXAMPLE
        Remove-ADTestSecretVault -GlobalVault -Force
        Removes a global vault (AllUsers scope) without prompts

    .OUTPUTS
        PSCustomObject containing vault removal results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - All secrets in the vault will be permanently deleted
        - Vault configuration will be removed from the system
        - This operation cannot be undone
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$ResetSecretStore,
        
        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Remove-ADTestSecretVault - CorrelationId: $correlationId"
        
        $result = @{
            CorrelationId = $correlationId
            VaultName = $VaultName
            VaultExists = $false
            VaultRemoved = $false
            SecretsRemoved = 0
            SecretStoreReset = $false
            Errors = @()
            Warnings = @()
        }
    }

    process {
        try {
            # -GlobalVault has to be read here, not merely declared. New-ADTestSecretVault
            # creates an AllUsers scope vault only when elevated, and that registration is
            # machine-wide, so removing it needs the same elevation. The switch was
            # previously declared, documented with its own example, and threaded all the way
            # down from Remove-ADEnvironment - and then never read. An unelevated global
            # teardown therefore failed with whatever error SecretManagement happened to
            # raise, instead of the clear warning the creation path gives.
            if ($GlobalVault) {
                if (Test-ADTestAdministrator) {
                    Write-Verbose 'Removing global vault (AllUsers scope) as administrator'
                }
                else {
                    $notAdmin = 'GlobalVault requested but not running as administrator - ' +
                                'an AllUsers scope vault cannot be unregistered'
                    Write-Warning $notAdmin
                    $result.Warnings += $notAdmin
                }
            }

            # Check if SecretStore modules are available
            $modulesAvailable = $true
            try {
                Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop
                Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction Stop
                Write-Verbose "SecretStore modules imported successfully"
            }
            catch {
                $modulesAvailable = $false
                $result.Warnings += "SecretStore modules not available - vault may not exist"
                Write-Verbose "SecretStore modules not available: $($_.Exception.Message)"
            }

            if ($modulesAvailable) {
                # Check if vault exists
                $existingVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
                
                if ($existingVault) {
                    $result.VaultExists = $true
                    Write-Verbose "Found vault '$VaultName' - proceeding with removal"
                    
                    try {
                        # Delete the secrets before unregistering the vault.
                        #
                        # Unregister-SecretVault does NOT remove them. It removes the vault
                        # REGISTRATION; the secrets stay in the SecretStore backing store
                        # indefinitely. The previous version counted them, reported that
                        # number as SecretsRemoved, and deleted none - so a teardown claimed
                        # to have cleaned up and left everything behind. Every run since the
                        # module was written has been accumulating them.
                        #
                        # Filtered on the Source metadata that Set-ADTestPasswordSecret
                        # stamps, and NOT on everything the vault can enumerate. SecretStore
                        # is a single store per user: every registered vault name sees the
                        # SAME secrets, so deleting all of them would destroy secrets that
                        # belong to other vaults and other tools.
                        #
                        # Enumeration is attempted whether or not -Force was passed. It was
                        # previously skipped under -Force to avoid a password prompt, which
                        # meant the common unattended path never cleaned anything at all. A
                        # locked store simply throws here, and that is handled below.
                        $ownedSecrets = @()

                        try {
                            $ownedSecrets = @(Get-SecretInfo -Vault $VaultName -ErrorAction Stop |
                                Where-Object { $_.Metadata -and $_.Metadata['Source'] -eq 'ADTestEnvironment' })
                            Write-Verbose "Vault reports $($ownedSecrets.Count) secret(s) created by this module"
                        }
                        catch {
                            Write-Verbose ("Cannot enumerate vault contents (the store may be locked): " +
                                "$($_.Exception.Message)")
                            $result.Errors += ("Could not enumerate secrets in '$VaultName': " +
                                "$($_.Exception.Message)")
                        }

                        $secretCountMsg = if ($ownedSecrets.Count -gt 0) {
                            "$($ownedSecrets.Count) secrets"
                        }
                        else {
                            'contents'
                        }

                        if ($Force -or $PSCmdlet.ShouldProcess("SecretStore Vault: $VaultName", ("Remove vault " +
                            "and $secretCountMsg"))) {
                            # SecretsRemoved counts what was actually deleted, not what was
                            # found. The two differing is the whole reason this was wrong.
                            foreach ($secret in $ownedSecrets) {
                                try {
                                    Remove-Secret -Name $secret.Name -Vault $VaultName -ErrorAction Stop
                                    $result.SecretsRemoved++
                                }
                                catch {
                                    Write-Verbose ("Failed to remove secret '$($secret.Name)': " +
                                        "$($_.Exception.Message)")
                                    $result.Errors += ("Could not remove secret '$($secret.Name)': " +
                                        "$($_.Exception.Message)")
                                }
                            }

                            Unregister-SecretVault -Name $VaultName -ErrorAction Stop
                            $result.VaultRemoved = $true

                            Write-Verbose "Successfully removed vault: $VaultName"
                            Write-Verbose "Removed $($result.SecretsRemoved) secret(s) created by this module"
                        }
                        else {
                            Write-Verbose "Vault removal cancelled by ShouldProcess"
                        }
                        
                    }
                    catch {
                        $errorMsg = "Failed to remove vault '$VaultName': $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        Write-Error $errorMsg
                    }
                }
                else {
                    Write-Verbose "Vault '$VaultName' does not exist - nothing to remove"
                    $result.Warnings += "Vault '$VaultName' was not found (may have been already removed)"
                }

                # Reset SecretStore configuration if requested
                if ($ResetSecretStore) {
                    try {
                        Write-Verbose "Resetting SecretStore configuration..."
                        
                        # Check if SecretStore is configured
                        $storeConfig = Get-SecretStoreConfiguration -ErrorAction SilentlyContinue
                        
                        if ($storeConfig) {
                            if ($Force -or $PSCmdlet.ShouldProcess("SecretStore Configuration", ("Reset to no " +
                                "authentication"))) {
                                # Reset SecretStore using proper parameters
                                try {
                                    # Try to reset with the known default password and set to no authentication
                                    $defaultPassword = Get-ADTestDefaultVaultPassword
                                    $resetArgs = @{
                                        Password       = $defaultPassword
                                        Authentication = 'None'
                                        Interaction    = 'None'
                                        Force          = $true
                                        ErrorAction    = 'Stop'
                                    }
                                    Reset-SecretStore @resetArgs
                                    Write-Verbose "SecretStore reset with known password to no authentication"
                                }
                                catch {
                                    # If that fails, try resetting to no authentication
                                    # without specifying the current password
                                    Write-Verbose "Trying alternative reset method: $($_.Exception.Message)"
                                    $fallbackArgs = @{
                                        Authentication = 'None'
                                        Interaction    = 'None'
                                        Force          = $true
                                        ErrorAction    = 'Stop'
                                    }
                                    Reset-SecretStore @fallbackArgs
                                    Write-Verbose "SecretStore reset to no authentication"
                                }
                                
                                $result.SecretStoreReset = $true
                                Write-Verbose ("Successfully reset SecretStore configuration (no authentication " +
                                    "required)")
                            }
                            else {
                                Write-Verbose "SecretStore reset cancelled by ShouldProcess"
                            }
                        }
                        else {
                            Write-Verbose "SecretStore is not configured - nothing to reset"
                        }
                    }
                    catch {
                        $errorMsg = "Failed to reset SecretStore configuration: $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        Write-Warning $errorMsg
                    }
                }
            }
            
        }
        catch {
            $errorMsg = "Failed to remove AD test secret vault: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
    }

    end {
        Write-Verbose "Completed Remove-ADTestSecretVault - CorrelationId: $correlationId"
        return [PSCustomObject]$result
    }
}
