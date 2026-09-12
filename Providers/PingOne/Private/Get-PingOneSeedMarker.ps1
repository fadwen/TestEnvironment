function Get-PingOneSeedMarker {
    <#
    .SYNOPSIS
        Returns the prefix and tag this provider stamps on everything it creates

    .DESCRIPTION
        A thin wrapper over Core's marker, so that every function in this provider asks one
        question rather than reading the connection and reaching into Core itself.

        Where the tag is stored differs by object type, because PingOne gives them different
        fields to store it in, and that difference is the whole reason this provider needs a
        custom user attribute:

        - A group, an application, a population and a resource each have a `description`, which
          is free text nobody else writes. The tag goes there.
        - A user has none. Verified against a live environment, a user object carries account,
          address, email, enabled, identityProvider, lifecycle, mfaEnabled, name, population,
          username and verifyStatus, and not one of them is a field this module could own
          without overwriting something a person might care about. So a seeded user carries the
          tag in a custom schema attribute the seed itself creates.

        The value never differs between object types. It is the module-wide tag from Core, so
        every seeded object in the environment can be found by one string.

    .PARAMETER Prefix
        The prefix, bare or with a trailing separator. Defaults to the connected prefix, and
        then to the module default.

    .OUTPUTS
        PSCustomObject with Prefix and Tag.

    .EXAMPLE
        PS> Get-PingOneSeedMarker

        DESCRIPTION: Returns the marker for the connected environment
        OUTPUT: Prefix ZZ-TEST- and Tag ZZ-TEST-seed
        USE CASE: Called by every function that names or claims an object

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Prefix
    )

    if (-not $Prefix) {
        if ($script:PingOneConnection) { $Prefix = $script:PingOneConnection.Prefix }
        else { $Prefix = $script:TestEnvironmentDefaultPrefix }
    }

    # Core validates the separator form. This provider stores the prefix exactly as the
    # connection took it, which may be bare, so the separator is put back before asking.
    $separatorPrefix = if ($Prefix -match '[-_]$') { $Prefix } else { '{0}-' -f $Prefix }

    return Get-TestSeedMarker -Prefix $separatorPrefix
}
