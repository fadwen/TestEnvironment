function Get-TestEnvironmentRuntime {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Reports which PowerShell the module is running on and which methods it is using because of it
    #>
    [CmdletBinding()]
    [OutputType('TestEnvironmentRuntime')]
    param()

    Get-TestRuntime
}
