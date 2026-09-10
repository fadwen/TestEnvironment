function Get-AuthentikServiceAccountName {
    <#
    .SYNOPSIS
        Returns the reserved username of the module's automation service account

    .DESCRIPTION
        The service account New-AuthentikServiceApp creates is a user like any other, under
        the seed path and carrying the seed tag, and it is the one seeded user that teardown
        must not delete while it is still the credential in use. It is told apart by its
        username alone, which is why that username is derived in exactly one place: a
        teardown that computed it differently from the bootstrap would delete the account it
        was authenticating with, halfway through.

    .PARAMETER Marker
        The seed marker to derive from. Defaults to the active connection's.

    .OUTPUTS
        System.String. The username, for example 'zz-test-automation'.

    .EXAMPLE
        PS> Get-AuthentikServiceAccountName

        DESCRIPTION: Derives the automation account's username for the active connection
        OUTPUT: zz-test-automation
        USE CASE: The bootstrap when creating it; ownership discovery when excluding it

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [PSObject]$Marker
    )

    if (-not $Marker) { $Marker = Get-AuthentikSeedMarker }
    return '{0}-automation' -f $Marker.SlugPrefix
}
