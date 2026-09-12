function Get-ADTestDnsZoneObject {
    <#
    .SYNOPSIS
        Finds the directory object behind a DNS zone, wherever the partition it lives in

    .DESCRIPTION
        An Active Directory-integrated zone is a directory object, which is what lets this
        provider stamp it with the seed tag and prove later that it created it. Finding that
        object is not as simple as asking for it, because it does not live in the domain
        naming context: a zone replicated to the domain sits under
        `DC=DomainDnsZones,<domain>`, one replicated to the forest under
        `DC=ForestDnsZones,<forest>`, and a legacy one under `CN=MicrosoftDNS,CN=System`.

        A `Get-ADObject` with no search base only looks in the domain naming context, so it
        finds none of the first two and silently returns nothing. That is not a loud failure:
        the zone gets created, the tag never gets written, and teardown then refuses to
        remove a zone this module made because it cannot prove it. That happened, which is
        why the search base is explicit here and why all three partitions are tried.

    .PARAMETER ZoneName
        The DNS zone name, as the DNS server reports it.

    .PARAMETER DomainDN
        The domain's distinguished name. Defaults to the connected domain's.

    .OUTPUTS
        The directory object, or nothing when the zone is not directory-integrated.

    .EXAMPLE
        PS> Get-ADTestDnsZoneObject -ZoneName 'zz-test-lab.ad.contoso.com'

        DESCRIPTION: Finds the object so it can be tagged or checked
        OUTPUT: An ADObject with its adminDescription
        USE CASE: Called when the zone is created, and again at teardown to prove ownership

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ZoneName,

        [Parameter()]
        [string]$DomainDN
    )

    if (-not $DomainDN) { $DomainDN = (Get-ADTestDomain).DomainDN }

    # The forest partition's name is the forest root, which is the domain's own name unless
    # this is a child domain; deriving it from the domain DN is close enough to try.
    $searchBases = @(
        "DC=DomainDnsZones,$DomainDN"
        "DC=ForestDnsZones,$DomainDN"
        "CN=MicrosoftDNS,CN=System,$DomainDN"
    )

    foreach ($searchBase in $searchBases) {
        try {
            $found = Get-ADObject -LDAPFilter "(&(objectClass=dnsZone)(name=$ZoneName))" `
                -SearchBase $searchBase -Properties adminDescription -ErrorAction Stop |
                Select-Object -First 1
            if ($found) {
                Write-Verbose "Zone '$ZoneName' found under $searchBase"
                return $found
            }
        }
        catch {
            Write-Verbose "Partition $searchBase did not answer: $($_.Exception.Message)"
        }
    }

    Write-Verbose "No directory object found for zone '$ZoneName'"
    return $null
}
