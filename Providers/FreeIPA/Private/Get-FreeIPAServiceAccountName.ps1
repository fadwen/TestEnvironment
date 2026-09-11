function Get-FreeIPAServiceAccountName {
    <#
    .SYNOPSIS
        Returns the reserved login of the module's automation service account

    .DESCRIPTION
        The service account New-FreeIPAServiceApp creates is a user like any other, carrying
        the seed tag in its class, and it is the one seeded user that teardown must not delete
        while it is still the credential in use. It is told apart by its login alone, which is
        why that login is derived in exactly one place: a teardown that computed it
        differently from the bootstrap would delete the account it was authenticating with,
        halfway through.

    .PARAMETER Marker
        The seed marker to derive from. Defaults to the active connection's.

    .OUTPUTS
        System.String. The login, for example 'zz-test-automation'.

    .EXAMPLE
        PS> Get-FreeIPAServiceAccountName

        DESCRIPTION: Derives the automation account's login for the active connection
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

    if (-not $Marker) { $Marker = Get-FreeIPASeedMarker }
    return '{0}automation' -f $Marker.NamePrefix
}
