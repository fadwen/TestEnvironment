function Update-TestContainment {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Places any seeded object that is not in its container
    #>

    # SupportsShouldProcess is declared but ShouldProcess is never called here. Both halves are
    # deliberate. Declaring it is what makes -WhatIf and -Confirm bind at all: they are optional
    # common parameters, so a wrapper that omits it rejects "-WhatIf" as an unknown parameter
    # rather than forwarding it - which is how a dispatch layer silently takes -WhatIf away from
    # every command behind it. Not calling it is what keeps the prompt in one place: the
    # provider function does the work, knows what it is about to touch, and carries its own
    # ConfirmImpact. A wrapper that prompted as well would ask twice for one action.
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Declared so -WhatIf and -Confirm bind and forward; the provider function behind this one calls ShouldProcess, and prompting here as well would ask twice for one action.')]
    param()

    dynamicparam {
        return Get-TestProviderParameter -CommandName ('Update-{0}Containment' -f $script:ActiveProvider)
    }

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $target = 'Update-{0}Containment' -f $script:ActiveProvider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $($script:ActiveProvider) provider does not implement $target." -ErrorAction Stop
            return
        }

        & $target @PSBoundParameters
    }
}
