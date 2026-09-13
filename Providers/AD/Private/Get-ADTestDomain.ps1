function Get-ADTestDomain {
    <#
    .SYNOPSIS
        Returns the domain the provider is working against, and its distinguished name

    .DESCRIPTION
        Every AD provider function needs the domain DN to build an OU path, so this is asked for
        constantly and must give the same answer every time within a session.

        The connection recorded by Connect-ADEnvironment is therefore authoritative when there is
        one. Re-detecting per call would let a session that started against one domain quietly
        continue against another - a machine can be re-joined, and USERDNSDOMAIN can be set by
        hand - and every function that builds a path from it would follow without complaint.

        Detection only runs when nothing is connected, which keeps the helper usable on its own.

    .OUTPUTS
        System.Collections.Hashtable with DNSName, DomainDN and ForestDN. ForestDN is the forest
        root's distinguished name, which differs from DomainDN in a child domain; when nothing is
        connected it is derived from the detected domain's forest, or falls back to DomainDN.

    .EXAMPLE
        PS> Get-ADTestDomain

        DESCRIPTION: Returns the connected domain, detecting one if nothing is connected
        OUTPUT: @{ DNSName = 'ad.contoso.com'; DomainDN = 'DC=ad,DC=contoso,DC=com'; ForestDN = 'DC=ad,DC=contoso,DC=com' }
        USE CASE: Called by every function that builds a distinguished name

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:ADConnection) {
        return @{
            DNSName  = $script:ADConnection.DNSName
            DomainDN = $script:ADConnection.DomainDN
            ForestDN = $script:ADConnection.ForestDN
        }
    }

    try {
        # USERDNSDOMAIN first: it is set on any domain-joined session and costs nothing, where
        # Get-ADDomain is a directory call.
        $dnsDomain = $env:USERDNSDOMAIN
        $forestName = $null
        if ([string]::IsNullOrEmpty($dnsDomain)) {
            $currentDomain = Get-ADDomain -Current LocalComputer -ErrorAction SilentlyContinue
            if ($currentDomain) {
                $dnsDomain = $currentDomain.DNSRoot
                $forestName = $currentDomain.Forest
            }
        }

        if (-not $dnsDomain) { throw 'Could not detect domain' }

        # Every label becomes a DC component. The previous version enumerated the one, two and
        # three label cases and fell through to the first label alone for anything deeper, so a
        # four-label domain silently produced a DN one level below the root - and every OU path
        # built from it would have been wrong without erroring.
        $domainDN = ($dnsDomain.Split('.') | ForEach-Object { "DC=$_" }) -join ','

        # USERDNSDOMAIN says nothing about the forest, so the forest root is known only when
        # the directory was asked. Without it the domain's own DN is the best available answer,
        # which is exact in a single-domain forest.
        $forestDN = if ($forestName) {
            ($forestName.Split('.') | ForEach-Object { "DC=$_" }) -join ','
        }
        else {
            $domainDN
        }

        Write-Verbose "Detected domain: $dnsDomain (DN: $domainDN, forest: $forestDN)"

        return @{
            DNSName  = $dnsDomain
            DomainDN = $domainDN
            ForestDN = $forestDN
        }
    }
    catch {
        throw "Failed to detect domain: $($_.Exception.Message). Please ensure this is run on a domain-joined machine with the ActiveDirectory module available."
    }
}
