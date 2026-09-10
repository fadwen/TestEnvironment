<#
.SYNOPSIS
    Regenerates the ADTestEnvironment test stub modules from the real cmdlets.

.DESCRIPTION
    Reads the parameter surface of the real ActiveDirectory, SecretManagement and
    SecretStore cmdlets and writes an empty-bodied stub function for each. Run this on a
    host that actually has those modules - a domain controller with RSAT - then commit the
    result. See README.md beside this script for why the stubs exist.

    Parameter types are carried over only where the type ships with PowerShell itself. The
    AD types live in assemblies a CI runner has no way to load, so those parameters are
    emitted untyped and bind as [object].

.PARAMETER OutputPath
    Directory to write the stub module folders into. Defaults to this script's directory.

.EXAMPLE
    .\Update-ADTestStub.ps1 -OutputPath .
    Regenerates the stubs in place.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# SecretManagement is commonly installed only under the Windows PowerShell user path, which
# pwsh does not read. Add it so this script can be run from either edition.
$winPSModules = Join-Path $HOME 'Documents\WindowsPowerShell\Modules'
if (Test-Path -LiteralPath $winPSModules) {
    $env:PSModulePath = $winPSModules + [IO.Path]::PathSeparator + $env:PSModulePath
}

Import-Module ActiveDirectory
Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore
Import-Module GroupPolicy

$common = [System.Management.Automation.PSCmdlet]::CommonParameters +
          [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

# Only the cmdlets the module and its suites actually touch. Keeping the list explicit
# stops a stub drifting into a module-wide mirror of RSAT.
$sets = [ordered]@{
    'ActiveDirectory' = @(
        'Add-ADFineGrainedPasswordPolicySubject', 'Add-ADGroupMember', 'Get-ADComputer'
        'Get-ADDomain', 'Get-ADFineGrainedPasswordPolicy', 'Get-ADGroup', 'Get-ADGroupMember'
        'Get-ADObject', 'Get-ADOrganizationalUnit', 'Get-ADUser', 'New-ADComputer'
        'New-ADFineGrainedPasswordPolicy', 'New-ADGroup', 'New-ADObject'
        'New-ADOrganizationalUnit', 'New-ADUser', 'Remove-ADComputer'
        'Remove-ADFineGrainedPasswordPolicy', 'Remove-ADGroup', 'Remove-ADOrganizationalUnit'
        'Remove-ADUser', 'Set-ADComputer', 'Set-ADGroup', 'Set-ADObject'
        'Set-ADOrganizationalUnit', 'Set-ADUser'
    )
    'Microsoft.PowerShell.SecretManagement' = @(
        'Get-Secret', 'Get-SecretInfo', 'Get-SecretVault', 'Register-SecretVault'
        'Remove-Secret', 'Set-Secret', 'Set-SecretVaultDefault', 'Unregister-SecretVault'
    )
    'Microsoft.PowerShell.SecretStore' = @(
        'Get-SecretStoreConfiguration', 'Reset-SecretStore', 'Set-SecretStoreConfiguration'
        'Unlock-SecretStore'
    )
    'GroupPolicy' = @(
        'Get-GPO', 'Get-GPInheritance', 'New-GPO', 'New-GPLink', 'Remove-GPLink', 'Remove-GPO'
    )
}

$safeType = @(
    [string], [string[]], [bool], [bool[]], [int], [int[]], [long], [switch]
    [System.Security.SecureString], [System.Management.Automation.PSCredential]
    [timespan], [datetime], [guid], [hashtable], [byte[]], [scriptblock]
)

$header = @(
    '# GENERATED FILE - do not edit by hand. See Tests/Stubs/README.md.'
    '#'
    '# A stand-in for a module the CI runner does not have, so the suite can import'
    '# ADTestEnvironment and Pester can mock commands that would otherwise not exist.'
    '# Every function is empty: it exists only to reproduce the real binding surface,'
    '# so a call the real cmdlet would reject fails here too. Parameter types are'
    '# carried over wherever the type ships with PowerShell itself.'
    '#'
    '# The suppressions below are the point of the file, not an oversight. The'
    '# parameters are deliberately unused, and a body-less function can neither'
    '# handle a password nor call ShouldProcess.'
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',"
    "    Justification = 'Stub parameters reproduce real cmdlet binding surfaces.')]"
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',"
    "    Justification = 'Stubs have no body to guard; the attribute mirrors the real cmdlet.')]"
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',"
    "    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]"
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',"
    "    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]"
    'param()'
    ''
)

foreach ($moduleName in $sets.Keys) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $header | ForEach-Object { $lines.Add($_) }

    foreach ($name in $sets[$moduleName]) {
        $cmd = Get-Command $name

        $params = $cmd.Parameters.GetEnumerator() |
            Where-Object { $common -notcontains $_.Key } |
            Sort-Object Key

        # SupportsShouldProcess on the state-changing verbs, both because the real cmdlets
        # have it and because PSUseShouldProcessForStateChangingFunctions demands it.
        $verb = $name.Split('-')[0]
        $stateChanging = @('New', 'Set', 'Remove', 'Add', 'Reset', 'Register', 'Unregister')
        $binding = if ($verb -in $stateChanging) {
            '[CmdletBinding(SupportsShouldProcess)]'
        }
        else {
            '[CmdletBinding()]'
        }

        $lines.Add("function $name {")
        $lines.Add("    $binding")
        $lines.Add('    param(')

        $decl = foreach ($p in $params) {
            $type = $p.Value.ParameterType

            # The AD cmdlets declare things like -PasswordNeverExpires as Nullable[bool].
            # Unwrapping keeps the binding surface honest and stops the analyzer reading a
            # boolean as a plaintext password.
            $inner = [Nullable]::GetUnderlyingType($type)

            if ($inner -and $safeType -contains $inner) {
                "        [System.Nullable[$($inner.FullName)]]`$$($p.Key)"
            }
            elseif ($safeType -contains $type) {
                "        [$($type.FullName)]`$$($p.Key)"
            }
            else {
                "        `$$($p.Key)"
            }
        }

        $lines.Add(($decl -join ",`n"))
        $lines.Add('    )')
        $lines.Add('}')
        $lines.Add('')
    }

    $lines.Add('Export-ModuleMember -Function @(')
    $lines.Add((($sets[$moduleName] | ForEach-Object { "    '$_'" }) -join ",`n"))
    $lines.Add(')')

    $outDir = Join-Path $OutputPath $moduleName
    if ($PSCmdlet.ShouldProcess($outDir, 'Write stub module')) {
        $null = New-Item -ItemType Directory -Force -Path $outDir
        $target = Join-Path $outDir "$moduleName.psm1"
        Set-Content -LiteralPath $target -Value ($lines -join "`n") -Encoding UTF8
        Write-Verbose "Wrote $target"
    }
}
