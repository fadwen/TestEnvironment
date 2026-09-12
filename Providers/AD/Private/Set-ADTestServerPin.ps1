function Set-ADTestServerPin {
    <#
    .SYNOPSIS
        Pins every AD and DNS call this provider makes to one domain controller

    .DESCRIPTION
        The provider calls the RSAT cmdlets from more than two hundred places, and none of
        them named a server: each one relied on automatic discovery instead. That is fine
        until a domain registers a controller it is not running, at which point discovery
        starts handing back the dead one and calls begin failing - not at the start, where it
        would be obvious, but whenever the discovery cache happens to re-resolve. A seed can
        get three steps in and then fail the rest, which is how this was found.

        Rather than edit every call site, this sets `$PSDefaultParameterValues` in the
        module's own scope, which reaches the provider's functions when they call the RSAT
        cmdlets. Three things make that safe:

        - It is module scope, not global, so nothing is written into the caller's session and
          nothing survives `Remove-Module`.
        - A command that has no `-Server` parameter is unaffected, so the provider's own
          `*-ADTest*` functions are untouched even though they match the wildcard.
        - A caller who has deliberately set their own default for these cmdlets still wins,
          which is the right way round.

        `Disconnect-ADEnvironment` clears it, and so does connecting somewhere else.

    .PARAMETER Server
        The domain controller to pin to.

    .PARAMETER Clear
        Remove the pin instead of setting one.

    .EXAMPLE
        PS> Set-ADTestServerPin -Server 'DC01.ad.contoso.com'

        DESCRIPTION: Points every later AD and DNS call at one controller
        OUTPUT: None
        USE CASE: Called by Connect-ADEnvironment once it has found one that answers

    .EXAMPLE
        PS> Set-ADTestServerPin -Clear

        DESCRIPTION: Removes the pin
        OUTPUT: None
        USE CASE: Called by Disconnect-ADEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Sets a module-scope preference variable; changes nothing outside the session.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Server,

        [Parameter()]
        [switch]$Clear
    )

    if (-not $script:PSDefaultParameterValues) {
        $script:PSDefaultParameterValues = @{}
    }

    foreach ($key in '*-AD*:Server', '*-DnsServer*:ComputerName') {
        $null = $script:PSDefaultParameterValues.Remove($key)
    }

    if ($Clear -or [string]::IsNullOrWhiteSpace($Server)) {
        Write-Verbose 'Cleared the domain controller pin'
        return
    }

    # The RSAT cmdlets take -Server; the DNS server cmdlets call the same thing -ComputerName.
    $script:PSDefaultParameterValues['*-AD*:Server'] = $Server
    $script:PSDefaultParameterValues['*-DnsServer*:ComputerName'] = $Server
    Write-Verbose "Pinned every AD and DNS call to $Server"
}
