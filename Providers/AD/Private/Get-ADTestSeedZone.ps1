function Get-ADTestSeedZone {
    <#
    .SYNOPSIS
        Derives the DNS zones the seed owns, and the address range behind them

    .DESCRIPTION
        A seeded computer has to resolve, and an A record for a machine that does not exist,
        written into the domain's own zone, is a record in somebody's production DNS with
        only its name to say it is ours. So the seed keeps zones of its own: a forward zone
        that is a child of the domain and carries the prefix in its name, and a reverse zone
        for a private range nothing real should be using.

        Both are Active Directory-integrated, which is what makes ownership provable the same
        way everything else in this provider is: the zone is a directory object, so it takes
        the seed tag in `adminDescription` and teardown can refuse a zone that does not carry
        it. That is the whole reason for preferring a DS-integrated zone over a file-backed
        one here.

        The range is 10.214.0.0/16. The FreeIPA provider uses 10.213.0.0/16 for the same
        purpose, and keeping them apart means a hybrid estate can seed both without one
        provider's reverse zone answering for the other's addresses.

    .PARAMETER Marker
        The seed marker to derive from. Defaults to the active connection's.

    .PARAMETER Domain
        The domain to sit under, as Get-ADTestDomain returns it. Defaults to the active one.

    .OUTPUTS
        Hashtable with Forward, Reverse, Subnet and NetworkId.

    .EXAMPLE
        PS> Get-ADTestSeedZone

        DESCRIPTION: The zones for the connected domain
        OUTPUT: @{ Forward = 'zz-test-lab.ad.contoso.com'; Reverse = '214.10.in-addr.arpa'; Subnet = '10.214'; NetworkId = '10.214.0.0/16' }
        USE CASE: Creating the zones, naming a record, and proving a zone is ours at teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [PSObject]$Marker,

        [Parameter()]
        [hashtable]$Domain
    )

    if (-not $Marker) { $Marker = Get-ADTestSeedMarker }
    if (-not $Domain) { $Domain = Get-ADTestDomain }

    if ([string]::IsNullOrWhiteSpace($Domain.DNSName)) {
        throw 'The domain has no DNS name, so the seed zone cannot be resolved.'
    }

    # A DNS label cannot hold the prefix as it is written elsewhere: the trailing hyphen is
    # legal but the upper case is not conventional, so the zone takes the lower-case form,
    # the same one the FreeIPA provider uses for its own names.
    $label = ($Marker.Prefix.ToLowerInvariant() -replace '[^a-z0-9-]', '-').Trim('-')
    $octets = @($script:ADTestSeedSubnet -split '\.')
    [array]::Reverse($octets)

    return @{
        Forward   = '{0}-lab.{1}' -f $label, $Domain.DNSName
        Reverse   = '{0}.in-addr.arpa' -f ($octets -join '.')
        Subnet    = $script:ADTestSeedSubnet
        NetworkId = '{0}.0.0/16' -f $script:ADTestSeedSubnet
    }
}
