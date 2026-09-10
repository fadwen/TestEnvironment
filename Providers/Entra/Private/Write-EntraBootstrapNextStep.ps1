function Write-EntraBootstrapNextStep {
    <#
    .SYNOPSIS
        Tells the person who just signed in interactively what to run next

    .DESCRIPTION
        The interactive sign-in is the bootstrap credential and nothing else: it exists so a
        human can create the service app that every later session connects as. What a person
        needs the moment it succeeds is to know whether that has already been done, and the
        exact command for their situation - and before this existed they had to work that out
        from a warning that only appeared after they guessed wrong.

        Takes the scenario Get-EntraBootstrapState decided and writes one short banner: what
        was found in the tenant, what was found on this machine, and the command to run. The
        commands use the shared dispatcher names, because those are what the module exports;
        a provider command such as Connect-EntraEnvironment is not callable from a session.

        Written to the host rather than the output stream, for the same reason the bootstrap's
        own handover banner is: it is an instruction to a person, must survive a caller who is
        capturing or discarding the output, and -PassThru carries the data for anyone who wants
        it as an object.

    .PARAMETER State
        The state Get-EntraBootstrapState returned.

    .PARAMETER FullAccess
        The sign-in asked for the full delegated scope list, so the banner can say the session
        is able to do the whole job as itself rather than only bootstrap.

    .EXAMPLE
        PS> Write-EntraBootstrapNextStep -State (Get-EntraBootstrapState)

        DESCRIPTION: Prints the next-step banner for the active connection
        OUTPUT: Nothing on the pipeline; a banner on the host
        USE CASE: Called by Connect-EntraEnvironment at the end of an interactive sign-in

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'An instruction to the human who just signed in, naming the exact command to run next. It must survive a caller who is piping or suppressing the other streams, and the data is available as an object from Get-EntraBootstrapState.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSTypeName('EntraBootstrapState')]
        [PSObject]$State,

        [Parameter()]
        [switch]$FullAccess
    )

    $found = switch ($State.Scenario) {
        'ReadyToConnect' {
            "Service app '$($State.Applications | Where-Object ClientId -eq $State.RecordClientId | Select-Object -First 1 -ExpandProperty DisplayName)' exists in $($State.TenantName), and this machine holds its credential (key in $($State.KeyProtection))."
        }
        'AppWithoutCredential' {
            $names = ($State.Applications.DisplayName | Sort-Object) -join ', '
            $why = if ($State.RecordExists) { "the record on this machine names a different application ($($State.RecordClientId))" } else { 'this machine holds no credential record for it' }
            "Service app '$names' exists in $($State.TenantName), but $why."
        }
        'StaleRecord' {
            "This machine holds a credential record for $($State.TenantName), but the application it names ($($State.RecordClientId)) is no longer in the tenant."
        }
        'NothingYet' {
            "No service app in $($State.TenantName) yet, and no credential record on this machine."
        }
        'Unknown' {
            $held = if ($State.RecordExists) { 'This machine holds a credential record for it' } else { 'This machine holds no credential record for it' }
            "Could not list applications in $($State.TenantName) with this sign-in: $($State.CheckError). $held."
        }
    }

    $instruction = switch ($State.Scenario) {
        'ReadyToConnect' { 'You are connected as yourself for now. From the next session, connect app-only, or verify the stored credential first:' }
        'AppWithoutCredential' { 'Replace it with one this machine holds the key for:' }
        'StaleRecord' { 'Create a new one; the stale record will be overwritten:' }
        'NothingYet' { 'Create it now, while this sign-in still carries your authority to consent:' }
        'Unknown' { 'If the tenant already has a service app, connect with the record; otherwise create one:' }
    }

    Write-Host ''
    Write-Host "  $found" -ForegroundColor Green
    Write-Host "  $instruction" -ForegroundColor Green
    Write-Host ''
    foreach ($command in $State.Commands) {
        Write-Host "    $command" -ForegroundColor Cyan
    }
    Write-Host ''
    if ($FullAccess) {
        Write-Host '  Or stay connected as yourself: this session asked for every delegated scope the module' -ForegroundColor DarkGray
        Write-Host '  needs, so New-TestEnvironment and Remove-TestEnvironment work here too, audited as you.' -ForegroundColor DarkGray
        Write-Host ''
    }
}
