function Get-OktaSeedTag {
    <#
    .SYNOPSIS
        Returns the shared seed tag for a prefix, in either of the forms this provider holds

    .DESCRIPTION
        The tag written into a seeded user's labSeedTag attribute and appended to a seeded
        object's description. It is Core's tag, so it is identical to the one the Entra and AD
        providers stamp.

        The normalisation exists because this provider carries its prefix bare - 'ZZ-TEST' -
        while Core derives the tag from the separator form, 'ZZ-TEST-'. The functions that
        identify a seeded object are handed the bare form, so each of them would otherwise have
        to remember to add the separator back before asking for the tag. Getting that wrong
        yields a tag that matches nothing, and a teardown that matches nothing quietly reports
        that there was nothing to remove.

    .PARAMETER Prefix
        The prefix, bare or with a trailing separator.

    .OUTPUTS
        System.String, the seed tag.

    .EXAMPLE
        PS> Get-OktaSeedTag -Prefix 'ZZ-TEST'

        DESCRIPTION: Derives the tag from the bare form this provider stores
        OUTPUT: ZZ-TEST-seed
        USE CASE: Called by the functions that identify seeded users and apps

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix
    )

    $separatorPrefix = if ($Prefix -match '[-_]$') { $Prefix } else { '{0}-' -f $Prefix }

    return (Get-TestSeedMarker -Prefix $separatorPrefix).Tag
}
