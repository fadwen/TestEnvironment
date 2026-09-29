function Get-OneLoginSeedMarker {
    <#
    .SYNOPSIS
        Returns the prefix and tag this provider stamps on everything it creates

    .DESCRIPTION
        A thin wrapper over Core's marker, so that every function in this provider asks one
        question rather than reading the connection and reaching into Core itself.

        Where the tag is stored differs by object type, because OneLogin gives them different
        fields to store it in:

        - An app has a description, which is free text nobody else writes. The tag goes there,
          inside the sentence Core provides, so an administrator who finds a seeded app in a
          production portal is told what made it and that it is safe to delete.
        - A user has none, so a seeded user carries the tag in a custom field the seed creates.
        - A role, a group and a mapping have nothing but a name. They are proved by what they
          hold instead - see Get-OneLoginSeededObject.

        The value never differs between object types. It is the module-wide tag from Core, so
        every seeded object in the account can be found by one string.

    .PARAMETER Prefix
        The prefix, bare or with a trailing separator. Defaults to the connected prefix, and
        then to the module default.

    .OUTPUTS
        PSCustomObject with Prefix, Tag, Description and DescriptionPattern.

    .EXAMPLE
        PS> Get-OneLoginSeedMarker

        DESCRIPTION: Returns the marker for the connected account
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
        if ($script:OneLoginConnection) { $Prefix = $script:OneLoginConnection.Prefix }
        else { $Prefix = $script:TestEnvironmentDefaultPrefix }
    }

    # Core validates the separator form. The connection stores the prefix exactly as it was
    # given, which may be bare, so the separator is put back before asking.
    $separatorPrefix = if ($Prefix -match '[-_]$') { $Prefix } else { '{0}-' -f $Prefix }

    return Get-TestSeedMarker -Prefix $separatorPrefix
}
