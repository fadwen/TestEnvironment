function Get-AuthentikSeedMarker {
    <#
    .SYNOPSIS
        Derives every form of the seed prefix an Authentik object can carry

    .DESCRIPTION
        One prefix, ZZ-TEST- by default, has to appear on Authentik objects in the forms each
        of them accepts. A group or application name takes it as written. A slug and a
        username must be lower case with no spaces, and Authentik rejects a trailing hyphen
        in a slug, so those take 'zz-test'. A user's path is a free string and takes the same
        lower-case form, which is what gives seeded users a container of their own to be
        enumerated by. The tag ZZ-TEST-seed goes into the free-form attributes every user and
        group carries, and into an application's description as a bracketed marker, because
        applications have no attributes.

        Deriving all of these here, from Core's Get-TestSeedMarker, is what keeps them in
        agreement. Each site computing its own lower-case version is how a slug and the path
        that finds it drift apart.

    .PARAMETER Connection
        The connection whose prefix to derive from. Defaults to the active one.

    .OUTPUTS
        AuthentikSeedMarker with Prefix, SlugPrefix, UserPath, Tag, Marker, Attribute and
        Description.

    .EXAMPLE
        PS> $marker = Get-AuthentikSeedMarker

        DESCRIPTION: Reads the forms for the active connection
        OUTPUT: Prefix 'ZZ-TEST-', SlugPrefix 'zz-test', Tag 'ZZ-TEST-seed', Marker '[ZZ-TEST-seed]'
        USE CASE: Naming an object at creation, and proving ownership at teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('AuthentikSeedMarker')]
    param(
        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }

    $shared = Get-TestSeedMarker -Prefix $Connection.Prefix
    $slugPrefix = ($shared.Prefix.ToLowerInvariant() -replace '[^a-z0-9-]', '-').TrimEnd('-')

    return [PSCustomObject]@{
        PSTypeName  = 'AuthentikSeedMarker'
        Prefix      = $shared.Prefix
        SlugPrefix  = $slugPrefix
        UserPath    = $slugPrefix
        Tag         = $shared.Tag
        Marker      = '[{0}]' -f $shared.Tag
        Attribute   = 'labSeedTag'
        Description = $shared.Description
    }
}
