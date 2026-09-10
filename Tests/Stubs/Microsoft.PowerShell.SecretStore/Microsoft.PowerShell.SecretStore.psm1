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

function Get-SecretStoreConfiguration {
    [CmdletBinding()]
    param(

    )
}

function Reset-SecretStore {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $Authentication,
        [System.Management.Automation.SwitchParameter]$Force,
        $Interaction,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Security.SecureString]$Password,
        [System.Int32]$PasswordTimeout,
        $Scope
    )
}

function Set-SecretStoreConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $Authentication,
        [System.Management.Automation.SwitchParameter]$Default,
        $Interaction,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Security.SecureString]$Password,
        [System.Int32]$PasswordTimeout,
        $Scope
    )
}

Export-ModuleMember -Function @(
    'Get-SecretStoreConfiguration',
    'Reset-SecretStore',
    'Set-SecretStoreConfiguration'
)
