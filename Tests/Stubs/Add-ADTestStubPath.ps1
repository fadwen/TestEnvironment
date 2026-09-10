<#
.SYNOPSIS
    Makes the stub modules discoverable so the suites can run without RSAT.

.DESCRIPTION
    ADTestEnvironment declares RequiredModules = @('ActiveDirectory') and the root module
    carries "#Requires -Module ActiveDirectory", so Import-Module fails outright on a host
    without RSAT. Pester has the same problem from the other side: it cannot mock a command
    that does not exist, so every SecretManagement mock fails where that module is absent.

    This appends the Stubs directory to PSModulePath, which fixes both. Appending rather
    than prepending is deliberate: a host that has the real module keeps using it and the
    suite exercises the true binding surface, while a host without it falls back to the
    stub. The GitHub windows-latest runner has neither module, so it takes the stub path.

    The stubs themselves are generated from the real cmdlets - see README.md beside this
    file. Nothing here weakens the mocks: the suites still mock every command they use.

.EXAMPLE
    . (Join-Path $PSScriptRoot '..\..\Stubs\Add-ADTestStubPath.ps1')

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding()]
param()

$stubRoot = $PSScriptRoot
$separator = [System.IO.Path]::PathSeparator
$current = @($env:PSModulePath -split $separator | Where-Object { $_ })

if ($current -notcontains $stubRoot) {
    $env:PSModulePath = (@($current) + $stubRoot) -join $separator
    Write-Verbose "Appended stub module path: $stubRoot"
}
