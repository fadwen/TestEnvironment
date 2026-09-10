function Get-EntraSeedMarker {
    <#
    .SYNOPSIS
        Returns the naming and ownership markers derived from the connection's prefix

    .DESCRIPTION
        Everything this module creates has to be identifiable later by a teardown that has no
        memory of the run that created it, and the tenant is expected to contain real objects
        that must never be mistaken for seeded ones.

        Two markers are used together, because neither is sufficient alone:

        - A name prefix, which is the only marker Graph will filter on server-side. Verified
          against a live tenant: startswith(displayName, ...) works for groups, devices,
          applications and service principals, and startswith(userPrincipalName, ...) works
          for users. It is what makes teardown a query rather than a full directory scan.
        - A seed tag, written into a field a real object would not carry. This cannot be
          filtered on - employeeType, companyName and every extensionAttribute are rejected
          by $filter with Request_UnsupportedQuery even with ConsistencyLevel eventual - so
          it is read back and checked client-side.

        The prefix alone is not enough to delete on. A tenant in real use will eventually
        contain something whose name happens to start with the prefix, and a deleted Entra
        object is recoverable for thirty days only if somebody notices within thirty days.

    .OUTPUTS
        EntraSeedMarker

    .EXAMPLE
        PS> $marker = Get-EntraSeedMarker

        DESCRIPTION: Derives the markers from the active connection's prefix
        OUTPUT: An object carrying the prefix, the seed tag and the UPN suffix
        USE CASE: Called by every create and every teardown function

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraSeedMarker')]
    param(
        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }

    # The prefix, tag and description come from Core, so all three providers stamp the same
    # thing and an object is recognisable as this module's work whichever directory it is
    # sitting in. This function survives only to add UpnSuffix, which is Entra's alone and
    # which eighteen callers already read off the marker.
    $shared = Get-TestSeedMarker -Prefix $Connection.Prefix

    return [PSCustomObject]@{
        PSTypeName         = 'EntraSeedMarker'
        Prefix             = $shared.Prefix
        Tag                = $shared.Tag
        Description        = $shared.Description
        DescriptionPattern = $shared.DescriptionPattern
        UpnSuffix          = $Connection.UpnSuffix
    }
}
