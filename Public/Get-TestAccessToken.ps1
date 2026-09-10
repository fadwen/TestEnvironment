function Get-TestAccessToken {
    <#
    .SYNOPSIS
        Returns the active provider's access token and its expiry

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
        TestAccessToken, or whatever the active provider returns.

    .EXAMPLE
        PS> Get-TestAccessToken

        DESCRIPTION: Runs against the connected provider
        OUTPUT: The provider's own result
        USE CASE: The normal path, after Connect-TestEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    param()

    dynamicparam {
        return Get-TestProviderParameter -CommandName ('Get-{0}AccessToken' -f $script:ActiveProvider)
    }

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $target = 'Get-{0}AccessToken' -f $script:ActiveProvider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $($script:ActiveProvider) provider does not implement $target." -ErrorAction Stop
            return
        }

        & $target @PSBoundParameters
    }
}
