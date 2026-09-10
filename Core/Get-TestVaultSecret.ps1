function Get-TestVaultSecret {
    <#
    .SYNOPSIS
        Reads the service app's private key back out of a SecretStore vault

    .DESCRIPTION
        The inverse of Set-TestVaultSecret, and the path Connect-TestEnvironment takes
        when the credential record says the key lives in a vault rather than the certificate
        store.

        The store is unlocked before the read rather than after a failure. A locked store's read
        error is a prompt on an interactive host and a hang on any other, so waiting to discover
        it is the one ordering that has no good outcome.

        If SecretManagement is absent the error names the fix rather than the symptom: the key
        is in a vault this machine cannot open, and either the module is installed or a new key
        is minted.

    .PARAMETER VaultName
        Vault holding the secret

    .PARAMETER SecretName
        Name of the secret

    .PARAMETER VaultPassword
        Password to unlock the store with. When none is supplied the module default is tried,
        then the default of each of the three earlier modules, because the store is shared per
        user and may have been configured by any of them.

    .OUTPUTS
        System.String, the base64-encoded PFX.

    .EXAMPLE
        PS> Get-TestVaultSecret -VaultName TestEnvironment -SecretName $name

        DESCRIPTION: Retrieves the stored private key
        OUTPUT: The base64-encoded PFX
        USE CASE: Called by Connect-TestEnvironment -UseSecretStore

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Default lab vault password, matching the one Initialize-TestSecretVault registers with.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
        Write-Error ("The private key is stored in the SecretStore vault '$VaultName', but " +
            'Microsoft.PowerShell.SecretManagement is not installed on this machine. Install it, or run ' +
            'New-TestServiceApp -Force to mint a new key.') -ErrorAction Stop
        return
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop -Verbose:$false

    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore) {
        Import-Module Microsoft.PowerShell.SecretStore -ErrorAction SilentlyContinue -Verbose:$false

        # The same ladder Initialize-TestSecretVault climbs, for the same reason. The store is
        # per USER and shared with everything that has ever configured it, and each of the
        # three earlier modules had its own default - so a store that OktaTestEnvironment set
        # up is one this module's default cannot open. Trying only the current default here
        # meant Connect-TestEnvironment -UseSecretStore failed on exactly the machines that
        # had used those modules, with a message telling the caller to unlock a store they
        # had never been asked for a password to.
        #
        # A caller who names a password gets that password alone: the legacy defaults are a
        # fallback for the unattended case, not an override of an explicit choice.
        $attempts = if ($VaultPassword) {
            @($VaultPassword)
        }
        else {
            foreach ($default in 'TestEnvironmentPassword', 'OktaTestEnvironmentPassword',
                                 'ADTestEnvironmentPassword', 'EntraTestEnvironmentPassword') {
                ConvertTo-SecureString -String $default -AsPlainText -Force
            }
        }

        foreach ($attempt in $attempts) {
            try {
                Unlock-SecretStore -Password $attempt -ErrorAction Stop
                break
            }
            catch {
                # Wrong password, or a store that needs no unlocking at all. Either way the
                # read below is the authority on whether the store is open, and its error
                # names the fix.
                Write-Verbose "Unlock-SecretStore declined this password: $($_.Exception.Message)"
            }
        }
    }

    $secret = $null
    try {
        $secret = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop
    }
    catch {
        throw (New-Object System.Exception(
            "Could not read secret '$SecretName' from vault '$VaultName': $($_.Exception.Message). " +
            'If the vault is locked, unlock it with Unlock-SecretStore.', $_.Exception))
    }

    if (-not $secret) {
        Write-Error "Secret '$SecretName' was not found in vault '$VaultName'." -ErrorAction Stop
        return
    }

    if ($secret -is [System.Security.SecureString]) {
        # Marshalled back rather than round-tripped through ConvertFrom-SecureString, which off
        # Windows returns hex-encoded plaintext instead of anything encrypted and would quietly
        # produce the wrong string here.
        $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }

    return [string]$secret
}
