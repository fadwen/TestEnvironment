function Test-TestEnvironment {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Verifies that what is seeded through the active provider matches the seed data
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    dynamicparam {
        return Get-TestProviderParameter -CommandName ('Test-{0}Environment' -f $script:ActiveProvider)
    }

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $target = 'Test-{0}Environment' -f $script:ActiveProvider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $($script:ActiveProvider) provider does not implement $target." -ErrorAction Stop
            return
        }

        & $target @PSBoundParameters
    }
}
