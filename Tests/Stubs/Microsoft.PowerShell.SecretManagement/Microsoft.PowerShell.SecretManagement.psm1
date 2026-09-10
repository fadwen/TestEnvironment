# GENERATED FILE - do not edit by hand. See Tests/Stubs/README.md.
#
# A stand-in for a module the CI runner does not have, so the suite can import
# ADTestEnvironment and Pester can mock commands that would otherwise not exist.
# Every function is empty: it exists only to reproduce the real binding surface,
# so a call the real cmdlet would reject fails here too. Parameter types are
# carried over wherever the type ships with PowerShell itself.
#
# The suppressions below are the point of the file, not an oversight. The
# parameters are deliberately unused, and a body-less function can neither
# handle a password nor call ShouldProcess.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Stub parameters reproduce real cmdlet binding surfaces.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
    Justification = 'Stubs have no body to guard; the attribute mirrors the real cmdlet.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]
param()

function Get-Secret {
    [CmdletBinding()]
    param(
        [System.Management.Automation.SwitchParameter]$AsPlainText,
        $InputObject,
        [System.String]$Name,
        [System.String]$Vault
    )
}

function Get-SecretInfo {
    [CmdletBinding()]
    param(
        [System.String]$Name,
        [System.String]$Vault
    )
}

function Get-SecretVault {
    [CmdletBinding()]
    param(
        [System.String[]]$Name
    )
}

function Register-SecretVault {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AllowClobber,
        [System.Management.Automation.SwitchParameter]$DefaultVault,
        [System.String]$Description,
        [System.String]$ModuleName,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Collections.Hashtable]$VaultParameters
    )
}

function Remove-Secret {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $InputObject,
        [System.String]$Name,
        [System.String]$Vault
    )
}

function Set-Secret {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.Hashtable]$Metadata,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$NoClobber,
        $Secret,
        $SecretInfo,
        [System.Security.SecureString]$SecureStringSecret,
        [System.String]$Vault
    )
}

function Set-SecretVaultDefault {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$ClearDefault,
        [System.String]$Name,
        $SecretVault
    )
}

function Unregister-SecretVault {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.String[]]$Name,
        $SecretVault
    )
}

Export-ModuleMember -Function @(
    'Get-Secret',
    'Get-SecretInfo',
    'Get-SecretVault',
    'Register-SecretVault',
    'Remove-Secret',
    'Set-Secret',
    'Set-SecretVaultDefault',
    'Unregister-SecretVault'
)
