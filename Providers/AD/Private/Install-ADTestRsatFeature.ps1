function Install-ADTestRsatFeature {
    <#
    .SYNOPSIS
        Installs the RSAT feature that provides one of the modules the AD provider needs

    .DESCRIPTION
        Only called when Connect-ADEnvironment was given -InstallRsat and the import failed.
        Installing RSAT is a machine-wide change that can reboot-pend, so it is never automatic.

        Two mechanisms, because Windows has two. A workstation gets the feature as an optional
        capability through Add-WindowsCapability; a server gets it as a Windows feature through
        Install-WindowsFeature, which lives in the ServerManager module and is absent on client
        SKUs. The capability route is tried first and the server route only if ServerManager is
        actually present, so neither path depends on guessing the SKU correctly.

        A domain controller already has both modules, so in practice this runs on a member
        server or an admin workstation.

    .PARAMETER Module
        Which module is missing: ActiveDirectory or GroupPolicy.

    .OUTPUTS
        System.Boolean, true when the feature is installed and the module should now import.

    .EXAMPLE
        PS> Install-ADTestRsatFeature -Module ActiveDirectory

        DESCRIPTION: Installs RSAT's AD DS tools
        OUTPUT: True on success
        USE CASE: Called by Connect-ADEnvironment -InstallRsat

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ActiveDirectory', 'GroupPolicy')]
        [string]$Module
    )

    $capability = switch ($Module) {
        'ActiveDirectory' { 'Rsat.ActiveDirectory.DS-LDS.Tools' }
        'GroupPolicy' { 'Rsat.GroupPolicy.Management.Tools' }
    }

    $feature = switch ($Module) {
        'ActiveDirectory' { 'RSAT-AD-PowerShell' }
        'GroupPolicy' { 'GPMC' }
    }

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install the RSAT feature providing $Module")) {
        return $false
    }

    if (Get-Command -Name Add-WindowsCapability -ErrorAction SilentlyContinue) {
        try {
            # -Name matches on a version-suffixed capability name, so the installed one is found
            # by prefix rather than by a version this module would have to keep current.
            $available = @(Get-WindowsCapability -Online -Name "$capability*" -ErrorAction Stop)
            $target = $available | Where-Object { $_.State -ne 'Installed' } | Select-Object -First 1

            if (-not $target) {
                Write-Verbose "$capability reports as already installed"
                return $true
            }

            $null = Add-WindowsCapability -Online -Name $target.Name -ErrorAction Stop
            Write-Verbose "Installed capability $($target.Name)"
            return $true
        }
        catch {
            Write-Verbose "Add-WindowsCapability could not install $capability : $($_.Exception.Message)"
        }
    }

    # ServerManager is absent on client SKUs, so its absence means this was never the right
    # route rather than that something went wrong.
    if (Get-Module -ListAvailable -Name ServerManager) {
        try {
            Import-Module ServerManager -ErrorAction Stop -Verbose:$false
            $null = Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction Stop
            Write-Verbose "Installed Windows feature $feature"
            return $true
        }
        catch {
            Write-Verbose "Install-WindowsFeature could not install $feature : $($_.Exception.Message)"
        }
    }

    return $false
}
