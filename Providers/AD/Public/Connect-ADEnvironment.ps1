function Connect-ADEnvironment {
    <#
    .SYNOPSIS
        Connects to an Active Directory domain, importing RSAT only now

    .DESCRIPTION
        There is nothing to authenticate here. Active Directory is reached with the caller's own
        Windows identity, so "connecting" means proving the four things every later call assumes
        and recording the answer:

        - The ActiveDirectory and GroupPolicy modules can be imported.
        - The session is elevated, because creating OUs and users needs it.
        - A domain can be reached and named.
        - The provider's seed data is on disk.

        Doing that once, here, is the point. Without it the first failure surfaces halfway
        through seeding, after some objects exist and some do not, and the message names a
        missing cmdlet rather than a missing feature.

        **The RSAT import happens here rather than in the manifest.** TestEnvironment declares no
        RequiredModules, and a contract test enforces it, because the providers do not share a
        platform: Entra and Okta reach a REST API from any host. Declaring ActiveDirectory in the
        manifest would make importing the module fail on a Linux container for somebody who only
        wanted to seed an Okta org. So the dependency is loaded at the moment it is genuinely
        needed, and its absence is reported as a sentence rather than a binding error.

    .PARAMETER Server
        Domain controller to work against. Defaults to whichever the machine would choose.

    .PARAMETER Credential
        Alternate credentials. Rarely wanted: the RSAT cmdlets use the caller's identity, and
        this is recorded so functions that accept -Credential can pass it on.

    .PARAMETER InstallRsat
        Install the RSAT AD and Group Policy features if they are missing. Requires elevation and
        is a machine-wide change, so it is opt-in rather than automatic.

    .PARAMETER PassThru
        Returns the connection summary

    .OUTPUTS
        ADEnvironmentConnection when -PassThru is supplied

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider AD

        DESCRIPTION: Verifies prerequisites and fixes the session on the local domain
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The normal path on a domain-joined workstation or a domain controller

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider AD -Server dc01.ad.contoso.com -PassThru

        DESCRIPTION: Pins the session to one domain controller
        OUTPUT: The connection, naming the domain and the controller
        USE CASE: Seeding against a specific controller so replication lag cannot confuse a re-read

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('ADEnvironmentConnection')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [switch]$InstallRsat,

        # Names every object this provider creates except the human user accounts, and names the
        # container they all live in. Setting it moves the whole tree, which is why it belongs
        # on the connection rather than on each seeding command.
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [switch]$PassThru
    )

    # Windows only, and worth saying plainly. The RSAT modules do not exist elsewhere, and the
    # error from a failed import would otherwise be about a missing module rather than a
    # platform that was never going to work.
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        Write-Error 'The AD provider needs the RSAT ActiveDirectory and GroupPolicy modules, which exist only on Windows. The Entra provider runs anywhere.' -ErrorAction Stop
        return
    }

    foreach ($name in 'ActiveDirectory', 'GroupPolicy') {
        if (Get-Module -Name $name) { continue }

        try {
            Import-Module -Name $name -ErrorAction Stop -Verbose:$false
            Write-Verbose "Imported $name"
        }
        catch {
            if ($InstallRsat) {
                Write-Verbose "Importing $name failed; attempting to install the RSAT feature"
                if (-not (Install-ADTestRsatFeature -Module $name)) {
                    Write-Error "Could not install the RSAT feature providing $name. Install it by hand, then connect again." -ErrorAction Stop
                    return
                }

                Import-Module -Name $name -ErrorAction Stop -Verbose:$false
            }
            else {
                Write-Error ("The $name module is not available, so the AD provider cannot run. " +
                    'Install RSAT (Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools ' +
                    'and Rsat.GroupPolicy.Management.Tools), or re-run with -InstallRsat.') -ErrorAction Stop
                return
            }
        }
    }

    if (-not (Test-ADTestAdministrator)) {
        Write-Error 'The AD provider needs an elevated session: creating organisational units, users and Group Policy objects all require it.' -ErrorAction Stop
        return
    }

    # Cleared first, so a failed reconnect cannot leave the previous domain in place and send
    # the next command somewhere the caller has stopped thinking about.
    $script:ADConnection = $null

    # A domain controller that answers, rather than whichever one DNS names first. A domain
    # can register more controllers than it is running, and discovery will hand back one that
    # has been switched off; pinning to a live one here is what stops a seed working for
    # twenty minutes and then failing halfway with a half-built directory behind it.
    try {
        $selectedServer = Select-ADTestServer -Server $Server -Credential $Credential
    }
    catch {
        Write-Error "Could not reach a domain: $($_.Exception.Message)" -ErrorAction Stop
        return
    }

    try {
        $domainParameter = @{ ErrorAction = 'Stop'; Server = $selectedServer }
        if ($Credential) { $domainParameter['Credential'] = $Credential }

        $domain = Get-ADDomain @domainParameter
    }
    catch {
        Write-Error "Could not reach a domain: $($_.Exception.Message)" -ErrorAction Stop
        return
    }

    # Set before the connection is recorded, because every distinguished name in this provider
    # is built from it.
    $script:ADTestRootName = '{0}TestData' -f $Prefix

    $script:ADConnection = [PSCustomObject]@{
        PSTypeName  = 'ADEnvironmentConnection'
        Prefix      = $Prefix
        RootOU      = $script:ADTestRootName
        SeedTag     = (Get-TestSeedMarker -Prefix $Prefix).Tag
        DNSName     = $domain.DNSRoot
        DomainDN    = $domain.DistinguishedName
        NetBIOSName = $domain.NetBIOSName
        Server      = $selectedServer
        Credential  = $Credential
        ConnectedAt = Get-Date
    }

    # Checked after the domain rather than before, because a broken install and an unreachable
    # domain are different problems and the domain is the one people actually hit.
    $null = Get-ADTestDataPath

    # Every AD and DNS call this provider makes now goes to the controller chosen above,
    # without each of the two hundred-odd call sites having to say so. This is module scope,
    # so it reaches the provider's own functions and does not leak into the caller's session;
    # Disconnect-ADEnvironment clears it. A command that has no such parameter is unaffected.
    Set-ADTestServerPin -Server $selectedServer

    Write-Verbose "Connected to $($domain.DNSRoot) ($($domain.DistinguishedName)) through $selectedServer"

    if ($PassThru) { return $script:ADConnection }
}
