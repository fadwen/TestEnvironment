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
        [System.String]$Domain,
        [System.Guid]$Guid,
        [System.String]$Name,
        [System.String]$Server
    )
}

function Get-GPInheritance {
    [CmdletBinding()]
    param(
        [System.String]$Domain,
        [System.String]$Server,
        [System.String]$Target
    )
}

function New-GPO {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.String]$Comment,
        [System.String]$Domain,
        [System.String]$Name,
        [System.String]$Server,
        [System.Guid]$StarterGpoGuid,
        [System.String]$StarterGpoName
    )
}

function New-GPLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.String]$Domain,
        $Enforced,
        [System.Guid]$Guid,
        $LinkEnabled,
        [System.String]$Name,
        [System.Int32]$Order,
        [System.String]$Server,
        [System.String]$Target
    )
}

function Remove-GPLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.String]$Domain,
        [System.Guid]$Guid,
        [System.String]$Name,
        [System.String]$Server,
        [System.String]$Target
    )
}

function Remove-GPO {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.String]$Domain,
        [System.Guid]$Guid,
        [System.Management.Automation.SwitchParameter]$KeepLinks,
        [System.String]$Name,
        [System.String]$Server
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
