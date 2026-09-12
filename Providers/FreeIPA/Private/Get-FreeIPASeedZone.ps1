function Get-FreeIPASeedZone {
    <#
    .SYNOPSIS
        Derives the DNS zones the seed owns, and the fingerprint that proves it

    .DESCRIPTION
        A seeded host has to resolve, and a record written into the realm's own zone would be
        a record in somebody's production DNS with only its name to say it is ours. So the
        seed keeps its own zones: a forward zone under the realm's domain that carries the
        prefix in its name, and a reverse zone for a private subnet nothing real uses. Every
        seeded host lives in the forward zone, which is why a host name is
        'zz-test-web01.zz-test-lab.ipa.example.com' and not 'zz-test-web01.ipa.example.com'.

        A reverse zone's name cannot carry a prefix, so ownership of both zones is the SOA
        contact: the seed writes 'hostmaster.<forward zone>.' as the administrator address
        of each zone it creates, and a zone is ours only when it carries that exact contact.
        An existing zone with the seed's name but another contact is refused, never adopted.

    .PARAMETER Marker
        The seed marker to derive from. Defaults to the active connection's.

    .PARAMETER Connection
        The connection whose domain the forward zone sits under. Defaults to the active one.

    .OUTPUTS
        FreeIPASeedZone with Forward, Reverse, Subnet and Contact.

    .EXAMPLE
        PS> Get-FreeIPASeedZone

        DESCRIPTION: Reads the zones for the active connection
        OUTPUT: Forward 'zz-test-lab.ipa.example.com', Reverse '213.10.in-addr.arpa.', Subnet '10.213.0.0/16', Contact 'hostmaster.zz-test-lab.ipa.example.com.'
        USE CASE: Naming a host, creating the zones, and proving a zone is ours at teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('FreeIPASeedZone')]
    param(
        [Parameter()]
        [PSObject]$Marker,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }
    if (-not $Marker) { $Marker = Get-FreeIPASeedMarker -Connection $Connection }
    if ([string]::IsNullOrWhiteSpace($Connection.Domain)) {
        throw 'The connection carries no domain, so the seed zone cannot be resolved.'
    }

    $forward = '{0}{1}.{2}' -f $Marker.NamePrefix, $script:FreeIPASeedZoneLabel, $Connection.Domain
    $octets = @($script:FreeIPASeedSubnet -split '\.')
    [array]::Reverse($octets)

    return [PSCustomObject]@{
        PSTypeName = 'FreeIPASeedZone'
        Forward    = $forward
        Reverse    = ('{0}.in-addr.arpa.' -f ($octets -join '.'))
        Subnet     = ('{0}.0.0/16' -f $script:FreeIPASeedSubnet)
        Contact    = ('hostmaster.{0}.' -f $forward)
    }
}
