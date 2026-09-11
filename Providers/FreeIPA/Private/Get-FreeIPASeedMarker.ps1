function Get-FreeIPASeedMarker {
    <#
    .SYNOPSIS
        Derives every form of the seed prefix a FreeIPA object can carry

    .DESCRIPTION
        One prefix, ZZ-TEST- by default, has to appear on FreeIPA objects in the form each of
        them accepts. FreeIPA lower-cases a user login and requires a group, host group,
        netgroup or rule name to match [a-zA-Z0-9_.][a-zA-Z0-9_.-]*, and a host name is a DNS
        label, so every prefixed name takes the lower-case form 'zz-test-'. The tag
        ZZ-TEST-seed goes into the userclass attribute of every user and host, which
        user-find and host-find can filter on, and into the description of everything else
        that has one as a bracketed marker.

        Deriving all of these here, from Core's Get-TestSeedMarker, is what keeps them in
        agreement. Each site computing its own lower-case version is how a name and the
        evidence that finds it drift apart.

    .PARAMETER Connection
        The connection whose prefix to derive from. Defaults to the active one.

    .OUTPUTS
        FreeIPASeedMarker with Prefix, NamePrefix, Tag, Marker, Attribute and Description.

    .EXAMPLE
        PS> $marker = Get-FreeIPASeedMarker

        DESCRIPTION: Reads the forms for the active connection
        OUTPUT: Prefix 'ZZ-TEST-', NamePrefix 'zz-test-', Tag 'ZZ-TEST-seed', Marker '[ZZ-TEST-seed]'
        USE CASE: Naming an object at creation, and proving ownership at teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('FreeIPASeedMarker')]
    param(
        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }

    $shared = Get-TestSeedMarker -Prefix $Connection.Prefix
    $namePrefix = ($shared.Prefix.ToLowerInvariant() -replace '[^a-z0-9._-]', '-')

    return [PSCustomObject]@{
        PSTypeName  = 'FreeIPASeedMarker'
        Prefix      = $shared.Prefix
        NamePrefix  = $namePrefix
        Tag         = $shared.Tag
        Marker      = '[{0}]' -f $shared.Tag
        Attribute   = 'userclass'
        Description = $shared.Description
    }
}
