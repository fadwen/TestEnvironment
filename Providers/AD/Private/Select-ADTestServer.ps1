function Select-ADTestServer {
    <#
    .SYNOPSIS
        Picks a domain controller that is actually answering, rather than whichever one DNS names first

    .DESCRIPTION
        A domain can have more than one domain controller registered and fewer than that
        running. Automatic discovery resolves the `_ldap._tcp.dc._msdcs` records and will
        happily hand back one that has been switched off for a month; the caller then gets
        "unable to find a default server with Active Directory Web Services running" from
        whichever command asked next. Worse, discovery is cached and re-resolved, so a run
        can work for twenty minutes and then start failing halfway through, leaving a
        half-built directory behind.

        This picks one that answers and returns its name, so every later call can be pinned
        to it. The order is deliberate:

        1. A server the caller named. If it does not answer, that is an error rather than a
           reason to look elsewhere - somebody who names a domain controller means it.
        2. The PDC emulator, which is the one this provider would have used anyway.
        3. Every other domain controller the domain knows, in the order the domain lists
           them.

        Each candidate is tried with a real call, because a name in DNS, a service that is
        listening and a directory that will answer a query are three different things, and
        only the third one matters.

    .PARAMETER Server
        A specific domain controller to use. Tried first, and its failure is fatal.

    .PARAMETER Credential
        The credential to test with, if the caller supplied one.

    .OUTPUTS
        System.String. The name of a domain controller that answered.

    .EXAMPLE
        PS> Select-ADTestServer

        DESCRIPTION: Finds a working domain controller in a domain with a stale registration
        OUTPUT: 'DC01.ad.contoso.com'
        USE CASE: Called by Connect-ADEnvironment, which pins every later call to the result

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    $common = @{ ErrorAction = 'Stop' }
    if ($Credential) { $common['Credential'] = $Credential }

    # One real query. Get-ADDomain goes through the same web service every other command in
    # this provider uses, so a candidate that satisfies it will satisfy them.
    $answers = {
        param($candidate)
        try {
            $null = Get-ADDomain -Server $candidate @common
            return $true
        }
        catch {
            Write-Verbose "Domain controller '$candidate' did not answer: $($_.Exception.Message)"
            return $false
        }
    }

    if ($Server) {
        if (& $answers $Server) { return $Server }
        throw ("The domain controller '$Server' did not answer. It was named explicitly, so no " +
            'other one was tried; omit -Server to let the provider choose one that is running.')
    }

    # Whatever discovery currently believes, so the common case costs one call and the
    # candidate list below is only built when that fails.
    $candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $discovered = Get-ADDomain @common
        if ($discovered.PDCEmulator) { $candidates.Add([string]$discovered.PDCEmulator) }
        foreach ($name in @($discovered.ReplicaDirectoryServers) + @($discovered.ReadOnlyReplicaDirectoryServers)) {
            if ($name -and -not $candidates.Contains([string]$name)) { $candidates.Add([string]$name) }
        }
    }
    catch {
        Write-Verbose "Discovery did not answer, so the domain controllers are read from DNS: $($_.Exception.Message)"
    }

    # Discovery itself failed, which is the case this function exists for. Ask DNS directly
    # for the domain controllers and try them one at a time.
    if ($candidates.Count -eq 0) {
        $domainName = $env:USERDNSDOMAIN
        if ($domainName) {
            try {
                $records = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$domainName" -Type SRV -ErrorAction Stop
                foreach ($record in @($records | Where-Object { $_.NameTarget })) {
                    $name = [string]$record.NameTarget
                    if ($name -and -not $candidates.Contains($name)) { $candidates.Add($name) }
                }
            }
            catch {
                Write-Verbose "Could not read the domain controller records from DNS: $($_.Exception.Message)"
            }
        }
    }

    # Insertion order, not alphabetical: the PDC emulator was put first on purpose.
    foreach ($candidate in $candidates) {
        if (& $answers $candidate) {
            Write-Verbose "Using domain controller '$candidate'"
            return $candidate
        }
    }

    if ($candidates.Count -eq 0) {
        throw ('No domain controller could be found at all. Check that this host is domain joined ' +
            'and that DNS resolves the domain.')
    }

    throw ("None of the $($candidates.Count) domain controller(s) the domain knows about answered: " +
        "$($candidates -join ', '). One of them may be registered in DNS but switched off; start it, " +
        'or remove its registration, or name a working one with -Server.')
}
