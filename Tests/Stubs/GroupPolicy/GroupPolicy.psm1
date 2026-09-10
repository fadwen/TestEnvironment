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

function Get-GPO {
    [CmdletBinding()]
    param(
        [System.Management.Automation.SwitchParameter]$All,
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Domain,
        $Guid,
        $Name,
        $Server
    )
}

function Get-GPInheritance {
    [CmdletBinding()]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Domain,
        $Server,
        $Target
    )
}

function New-GPO {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Comment,
        $Domain,
        $Name,
        $Server,
        $StarterGpoGuid,
        $StarterGpoName
    )
}

function New-GPLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Domain,
        $Enforced,
        $Guid,
        $LinkEnabled,
        $Name,
        $Order,
        $Server,
        $Target
    )
}

function Remove-GPLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Domain,
        $Guid,
        $Name,
        $Server,
        $Target
    )
}

function Remove-GPO {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $Domain,
        $Guid,
        [System.Management.Automation.SwitchParameter]$KeepLinks,
        $Name,
        $Server
    )
}

Export-ModuleMember -Function @(
    'Get-GPO',
    'Get-GPInheritance',
    'New-GPO',
    'New-GPLink',
    'Remove-GPLink',
    'Remove-GPO'
)
