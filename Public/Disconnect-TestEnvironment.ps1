function Disconnect-TestEnvironment {
    <#
    .SYNOPSIS
        Clears the stored connection for the active provider

    .DESCRIPTION
        Dispatches to the provider the session is connected through, which was fixed by
        Connect-TestEnvironment. The provider is deliberately not a parameter here: naming it
        again on every call is how a script ends up seeding one directory and tearing down
        another, and the connection already knows the answer.

        The provider's own parameters are mirrored onto this function at binding time, so
        provider-specific switches keep working through it with tab completion and validation
        intact, and a parameter the provider does not have fails at binding rather than being
        quietly dropped.

    .OUTPUTS
        TestEnvironmentDisconnectResult, or whatever the active provider returns.

    .EXAMPLE
        PS> Disconnect-TestEnvironment

        DESCRIPTION: Runs against the connected provider
        OUTPUT: The provider's own result
        USE CASE: The normal path, after Connect-TestEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
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
        return Get-TestProviderParameter -CommandName ('Disconnect-{0}Environment' -f $script:ActiveProvider)
    }

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $target = 'Disconnect-{0}Environment' -f $script:ActiveProvider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $($script:ActiveProvider) provider does not implement $target." -ErrorAction Stop
            return
        }

        & $target @PSBoundParameters
    }
}
