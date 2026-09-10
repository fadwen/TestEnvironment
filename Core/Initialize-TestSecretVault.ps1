function Initialize-TestSecretVault {
    <#
    .SYNOPSIS
        Makes sure a usable SecretStore vault exists, installing the modules if asked to

    .DESCRIPTION
        SecretManagement and SecretStore are deliberately absent from the manifest's
        RequiredModules, and a contract test enforces that. The module's zero-dependency promise
        is what lets it run on a locked-down host, and a required module would break that for
        everybody in order to serve the minority who opt into the vault. They are therefore
        imported here, on demand, only when -UseSecretStore is passed.

        Installing modules from the gallery onto somebody's machine is not something to do
        quietly, so it happens only under the explicit opt-in, is announced, and goes to
        CurrentUser scope so it needs no elevation.

        The vault is configured with Interaction disabled and a password supplied
        programmatically. Left at the default, SecretStore prompts for its password on first
        access, and a prompt in a script that was meant to run unattended is indistinguishable
        from a hang - the exact scenario a lab automation module exists to avoid.

    .PARAMETER VaultName
        The vault to register or reuse

    .PARAMETER VaultPassword
        Password for the vault. A default is used when none is supplied, for the same reason the
        seeded users have generated passwords nobody records: this protects a lab credential on
        a machine you already control, and prompting would defeat the automation.

    .PARAMETER Install
        Install the SecretManagement and SecretStore modules if they are missing

    .OUTPUTS
        TestVaultState with VaultName, Created and Available

    .EXAMPLE
        PS> Initialize-TestSecretVault -VaultName 'TestEnvironment' -Install

        DESCRIPTION: Registers the vault, installing the gallery modules if needed
        OUTPUT: An object reporting whether the vault was created and is usable
        USE CASE: Called by New-TestServiceApp -UseSecretStore

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Default lab vault password, overridable with -VaultPassword. It protects a lab credential on a machine the caller already controls, and prompting for it would deadlock every unattended run.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('TestVaultState')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$Install
    )

    $result = [PSCustomObject]@{
        PSTypeName = 'TestVaultState'
        VaultName  = $VaultName
        Created    = $false
        Available  = $false
    }

    foreach ($required in 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore') {
        if (Get-Module -ListAvailable -Name $required) { continue }

        if (-not $Install) {
            Write-Error ("$required is not installed. Re-run with -UseSecretStore to have it installed " +
                "automatically, or install it yourself with Install-Module $required -Scope CurrentUser.") -ErrorAction Stop
            return $result
        }

        if (-not $PSCmdlet.ShouldProcess($required, 'Install module from the PowerShell Gallery')) {
            Write-Error "$required is required for -UseSecretStore and was not installed." -ErrorAction Stop
            return $result
        }

        Write-Verbose "Installing $required from the PowerShell Gallery"
        Install-Module -Name $required -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop -Verbose:$false
    Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop -Verbose:$false

    if (-not $VaultPassword) {
        $VaultPassword = ConvertTo-SecureString -String 'TestEnvironmentPassword' -AsPlainText -Force
    }

    # SecretStore configuration is per USER, not per vault, and it is shared with anything else
    # already using it - ADTestEnvironment and OktaTestEnvironment both do. Once a password has
    # been set, Set-SecretStoreConfiguration refuses to set another: "already configured to
    # require a password, and a new password cannot be added". So the store is configured only
    # when it has never been configured, and otherwise left exactly as the caller has it.
    $state = Get-TestSecretStoreState

    if (-not $state.Configured) {
        if (-not $PSCmdlet.ShouldProcess('SecretStore', 'Configure for password authentication without prompting')) {
            return $result
        }

        # Interaction None is the part that matters. Left at the default, the store prompts on
        # first access, and a prompt in an unattended run is indistinguishable from a hang.
        Set-SecretStoreConfiguration -Authentication Password -Password $VaultPassword `
            -Interaction None -Confirm:$false -ErrorAction Stop
        Write-Verbose 'Configured SecretStore for unattended password authentication'
        $state.Authentication = 'Password'
    }
    else {
        # Never reconfigured. SecretStore configuration is per USER and shared with every other
        # module using it - ADTestEnvironment and OktaTestEnvironment both do - so changing it
        # here would change it for them. Whatever the store already is, this adapts to it.
        Write-Verbose "SecretStore is already configured (Authentication: $($state.Authentication)); leaving it alone"
    }

    if ($state.Authentication -eq 'Password') {
        # Unlocking an already-unlocked store is harmless; skipping it when the store happens
        # to be locked is not, so this runs either way. A failure is fatal rather than a
        # warning, because every read and write below would otherwise fail one at a time with
        # a less useful message.
        $unlocked = $false
        $attempts = @($VaultPassword)

        # Only when the caller named no password of their own. The store is per USER and was
        # very likely configured by one of the three modules that preceded this one, each with
        # its own default - so a machine that has used ADTestEnvironment or OktaTestEnvironment
        # has a store this module's default cannot open. Consolidating without this would tell
        # people to reset a store holding credentials that still work.
        #
        # Tried in order, and only after the current default has failed, so nothing here
        # weakens the store: these are this project's own published defaults, on the caller's
        # own machine, and the alternative is a working credential made unreachable by a rename.
        if (-not $PSBoundParameters.ContainsKey('VaultPassword')) {
            foreach ($legacy in 'OktaTestEnvironmentPassword', 'ADTestEnvironmentPassword', 'EntraTestEnvironmentPassword') {
                $attempts += (ConvertTo-SecureString -String $legacy -AsPlainText -Force)
            }
        }

        foreach ($attempt in $attempts) {
            try {
                Unlock-SecretStore -Password $attempt -ErrorAction Stop
                $unlocked = $true
                break
            }
            catch {
                $unlockError = $_
            }
        }

        if (-not $unlocked) {
            Write-Error ("Could not unlock SecretStore: $($unlockError.Exception.Message). SecretStore " +
                "configuration is per-user, so this one per-user store is shared with everything else that " +
                "has ever used it - ADTestEnvironment, OktaTestEnvironment and EntraTestEnvironment all " +
                "did, and their default passwords were tried here along with this module's. Pass " +
                "-VaultPassword with the existing password.") -ErrorAction Stop
            return $result
        }
    }
    else {
        Write-Verbose 'Store uses no authentication; no unlock needed'
    }

    $existing = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    if (-not $existing) {
        if (-not $PSCmdlet.ShouldProcess($VaultName, 'Register a SecretStore vault')) { return $result }

        Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -ErrorAction Stop
        $result.Created = $true
        Write-Verbose "Registered SecretStore vault '$VaultName'"
    }

    $result.Available = $true
    return $result
}
