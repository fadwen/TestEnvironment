function New-ADTestSecretVault {
    <#
    .SYNOPSIS
        Creates or configures a SecretStore vault for AD test environment passwords

    .DESCRIPTION
        Creates a computer-level SecretStore vault for storing AD test environment passwords.
        Configures the vault with appropriate security settings and access controls.
        
        The SecretStore itself is configured with no authentication for ease of automation,
        but individual vaults are password-protected for security.

    .PARAMETER VaultName
        Name of the secret vault to create. Defaults to "ADTestEnvironment"

    .PARAMETER VaultPassword
        Password for the secret vault. If not provided, defaults to "ADTestEnvironmentPassword"

    .PARAMETER UseDefaultPassword
        Use the default password "ADTestEnvironmentPassword" instead of prompting.
        Defaults to $true for automation.

    .PARAMETER Force
        Force recreation of the vault if it already exists

    .PARAMETER AllowPlaintextVault
        Allow creation of a vault without password protection (less secure, for testing only)

    .PARAMETER GlobalVault
        Create vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges for optimal security.

    .EXAMPLE
        New-ADTestSecretVault
        Creates the default ADTestEnvironment vault with default password "ADTestEnvironmentPassword"

    .EXAMPLE
        New-ADTestSecretVault -UseDefaultPassword:$false
        Creates the vault but prompts for password instead of using default

    .EXAMPLE
        New-ADTestSecretVault -VaultName "ProdVault" -VaultPassword $securePass
        Creates a custom named vault with specified password

    .EXAMPLE
        New-ADTestSecretVault -Force
        Recreates the vault even if it already exists

    .EXAMPLE
        New-ADTestSecretVault -GlobalVault
        Creates a global vault (AllUsers scope) - requires admin privileges

    .OUTPUTS
        PSCustomObject containing vault creation results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - SecretStore is configured with no authentication for automation ease
        - Individual vaults are password-protected using Windows Data Protection API
        - Vault is created at computer level for shared access when running as admin
        - Requires administrative privileges for optimal security
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper; the caller checks $WhatIfPreference before invoking it.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [Parameter()]
        [System.Security.SecureString]$VaultPassword,
        
        [Parameter()]
        [bool]$UseDefaultPassword = $true,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AllowPlaintextVault,
        
        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestSecretVault - CorrelationId: $correlationId"
        
        $result = @{
            CorrelationId = $correlationId
            VaultName = $VaultName
            VaultCreated = $false
            VaultExists = $false
            VaultConfigured = $false
            IsDefault = $false
            Errors = @()
            Warnings = @()
        }
        
        # Ensure SecretStore modules are available
        try {
            Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop
            Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction Stop
            Write-Verbose "SecretStore modules imported successfully"
        }
        catch {
            throw ("SecretStore modules not available. Run Test-ADTestSecretStorePrerequisite first. Error: " +
                "$($_.Exception.Message)")
        }
        
        # SecretStore configuration is per USER, not per vault, and it is shared with every
        # other module that registers a vault against it - OktaTestEnvironment and
        # EntraTestEnvironment both do, and both need Authentication = Password.
        #
        # This module prefers a passwordless store, but it must NOT impose that on a store it
        # did not configure: doing so re-encrypts the shared store and breaks the credentials
        # those modules keep in it. So the preference applies only when nothing has configured
        # the store yet, and otherwise whatever is found is adapted to.
        $storeConfigured = $false
        $needsConfiguration = $false
        $storeAuthentication = $null

        try {
            # Try to get configuration to see if SecretStore is set up
            $storeConfig = Get-SecretStoreConfiguration -ErrorAction Stop
            $storeAuthentication = [string]$storeConfig.Authentication

            # Check if store is accessible
            try {
                Get-SecretVault -ErrorAction Stop | Out-Null
                Write-Verbose "SecretStore is configured and accessible"
                $storeConfigured = $true

                if ($storeAuthentication -ne 'None') {
                    Write-Verbose ("SecretStore is configured with Authentication '$storeAuthentication' by " +
                        "this user or another module. Adapting to it rather than reconfiguring, because the " +
                        "store is shared.")
                }
            }
            catch {
                Write-Verbose "SecretStore configured but not accessible: $($_.Exception.Message)"
                $needsConfiguration = $true
            }
        }
        catch {
            # Get-SecretStoreConfiguration THROWS when the store is LOCKED, with "A valid
            # password is required to access the Microsoft.PowerShell.SecretStore vault". That
            # error is proof a password IS configured, not evidence that nothing is. Treating
            # it as "not configured" is what previously led straight into reconfiguring a store
            # another module owns.
            if ($_.Exception.Message -match 'valid password is required') {
                Write-Verbose ("SecretStore is configured with a password and is currently locked. Adapting " +
                    "to it rather than reconfiguring, because the store is shared per user.")
                $storeConfigured = $true
                $storeAuthentication = 'Password'
            }
            else {
                Write-Verbose "SecretStore not configured: $($_.Exception.Message)"
                $needsConfiguration = $true
            }
        }

        # Configured only when nothing has configured it yet. See the note above: this store is
        # shared, so a preference is not a licence to overwrite somebody else's setting.
        if ($needsConfiguration -and -not $storeConfigured) {
            try {
                Write-Verbose "Configuring SecretStore with no authentication (passwordless)..."
                $setSecretStoreConfigurationArgs1 = @{
                    Authentication = 'None'
                    Interaction    = 'None'
                    Scope          = 'CurrentUser'
                    Confirm        = $false
                    ErrorAction    = 'Stop'
                }
                Set-SecretStoreConfiguration @setSecretStoreConfigurationArgs1
                Write-Verbose ("Configured SecretStore with no authentication - individual vaults can still be " +
                    "password protected")
                $storeConfigured = $true
            }
            catch {
                $result.Warnings += ("Could not configure SecretStore automatically: $($_.Exception.Message). " +
                    "May prompt for password during vault creation.")
                Write-Warning ("Could not configure SecretStore automatically: $($_.Exception.Message). May " +
                    "prompt for password during vault creation.")
            }
        }

        # A store this module did not configure may require a password, in which case it has to
        # be unlocked before any secret can be written. Failing here is fatal rather than a
        # warning: every Set-Secret afterwards would otherwise fail one at a time with a message
        # about the secret rather than about the locked store.
        if ($storeAuthentication -eq 'Password') {
            $unlockPassword = $VaultPassword
            if (-not $unlockPassword -and $UseDefaultPassword) {
                $unlockPassword = Get-ADTestDefaultVaultPassword
            }

            if (-not $unlockPassword) {
                throw ("SecretStore on this machine requires a password and none was supplied. The store is " +
                    "shared per user with OktaTestEnvironment and EntraTestEnvironment; if one of those " +
                    "configured it, pass -VaultPassword with that password.")
            }

            try {
                Unlock-SecretStore -Password $unlockPassword -ErrorAction Stop
                Write-Verbose "Unlocked the shared SecretStore."
            }
            catch {
                throw ("Could not unlock SecretStore: $($_.Exception.Message). The store is configured with a " +
                    "password that is not this module's default - most likely because OktaTestEnvironment or " +
                    "EntraTestEnvironment configured it first, since all three share one per-user store. Pass " +
                    "-VaultPassword with the existing password.")
            }
        }
    }

    process {
        try {
            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
            
            if ($existingVault) {
                $result.VaultExists = $true
                Write-Verbose "Vault '$VaultName' already exists"
                
                if (-not $Force) {
                    Write-Verbose "Vault exists and Force not specified - skipping creation"
                    $result.VaultConfigured = $true
                    $result.Warnings += "Vault '$VaultName' already exists. Use -Force to recreate."
                    return [PSCustomObject]$result
                }
                else {
                    Write-Verbose "Force specified - removing existing vault"
                    try {
                        Unregister-SecretVault -Name $VaultName -ErrorAction Stop
                        Write-Verbose "Successfully removed existing vault: $VaultName"
                    }
                    catch {
                        $errorMsg = "Failed to remove existing vault '$VaultName': $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        throw $errorMsg
                    }
                }
            }
            
            # Prepare vault parameters - always use password for vault even though store has none
            $vaultParams = @{}
            
            if ($VaultPassword) {
                # Use provided password
                $vaultParams.Password = $VaultPassword
                Write-Verbose "Using provided vault password"
            }
            elseif ($UseDefaultPassword) {
                # Use default password for the vault. Held in one place rather than as a
                # literal here - see Get-ADTestDefaultVaultPassword for what it is and why
                # publishing it is acceptable for a test module.
                $vaultParams.Password = Get-ADTestDefaultVaultPassword
                Write-Verbose "Using the module's documented default vault password"
            }
            elseif ($AllowPlaintextVault) {
                # Create vault without password (less secure)
                $vaultParams.Authentication = 'None'
                $result.Warnings += "Vault created without password protection (less secure)"
                Write-Warning "Creating vault without password protection - this is less secure"
            }
            else {
                # Default to using our standard password if nothing specified
                $vaultParams.Password = Get-ADTestDefaultVaultPassword
                Write-Verbose "No password specified - using the documented default vault password"
            }
            
            # Configure vault scope based on GlobalVault parameter
            if ($GlobalVault) {
                # Shared with Remove-ADTestSecretVault. This check used to be inlined here
                # and absent there, which is how the remove side's -GlobalVault ended up
                # declared but never read.
                if (Test-ADTestAdministrator) {
                    Write-Verbose "Creating global vault (AllUsers scope) - running as administrator"
                    $vaultParams.Scope = 'AllUsers'
                }
                else {
                    Write-Warning ("GlobalVault requested but not running as administrator - using CurrentUser " +
                        "scope instead")
                    $vaultParams.Scope = 'CurrentUser'
                    $result.Warnings += ("GlobalVault requested but not running as administrator - vault " +
                        "created for current user only")
                }
            }
            else {
                Write-Verbose "Creating user-specific vault (CurrentUser scope)"
                $vaultParams.Scope = 'CurrentUser'
            }
            
            # Create the vault
            Write-Verbose "Creating SecretStore vault: $VaultName"
            try {
                if ($vaultParams.Count -gt 0) {
                    $registerSecretVaultArgs2 = @{
                        Name            = $VaultName
                        ModuleName      = 'Microsoft.PowerShell.SecretStore'
                        VaultParameters = $vaultParams
                        ErrorAction     = 'Stop'
                    }
                    Register-SecretVault @registerSecretVaultArgs2
                }
                else {
                    $registerSecretVaultArgs3 = @{
                        Name        = $VaultName
                        ModuleName  = 'Microsoft.PowerShell.SecretStore'
                        ErrorAction = 'Stop'
                    }
                    Register-SecretVault @registerSecretVaultArgs3
                }
                
                $result.VaultCreated = $true
                $result.VaultConfigured = $true
                Write-Verbose "Successfully created SecretStore vault: $VaultName"
            }
            catch {
                $errorMsg = "Failed to create SecretStore vault '$VaultName': $($_.Exception.Message)"
                $result.Errors += $errorMsg
                throw $errorMsg
            }
            
            # Verify vault creation
            $newVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
            if ($newVault) {
                Write-Verbose "Vault creation verified successfully"
                
                # Check if this is the default vault
                $defaultVault = Get-SecretVault | Where-Object { $_.IsDefault -eq $true }
                if (-not $defaultVault -or $defaultVault.Name -eq $VaultName) {
                    try {
                        Set-SecretVaultDefault -Name $VaultName -ErrorAction Stop
                        $result.IsDefault = $true
                        Write-Verbose "Set '$VaultName' as default secret vault"
                    }
                    catch {
                        $result.Warnings += "Failed to set as default vault: $($_.Exception.Message)"
                        Write-Warning "Failed to set '$VaultName' as default vault: $($_.Exception.Message)"
                    }
                }
            }
            else {
                $errorMsg = "Vault creation succeeded but vault verification failed"
                $result.Errors += $errorMsg
                throw $errorMsg
            }
            
        }
        catch {
            $errorMsg = "Failed to create AD test secret vault: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestSecretVault - CorrelationId: $correlationId"
        return [PSCustomObject]$result
    }
}
