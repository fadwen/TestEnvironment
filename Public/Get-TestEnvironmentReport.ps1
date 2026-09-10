function Get-TestEnvironmentReport {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Reports what is currently seeded through the active provider
    #>

    [CmdletBinding()]
    param()

    dynamicparam {
        return Get-TestProviderParameter -CommandName ('Get-{0}EnvironmentReport' -f $script:ActiveProvider)
    }

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $target = 'Get-{0}EnvironmentReport' -f $script:ActiveProvider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $($script:ActiveProvider) provider does not implement $target." -ErrorAction Stop
            return
        }

        & $target @PSBoundParameters
    }
}
