function Resolve-PingOneSeedName {
    <#
    .SYNOPSIS
        Turns a seed-file key into the name the object carries in the environment

    .DESCRIPTION
        The seed files hold bare keys - 'all-staff', 'expenses', 'awhitfield' - and the
        environment holds prefixed names. This is the one place the two are related, so every
        step names an object the same way and teardown finds what the seed made.

        Three forms, because PingOne constrains them differently:

        - A display name takes the prefix as written: 'All Staff' becomes 'ZZ-TEST-All Staff'.
          Groups, populations, applications and resources all use this.
        - A username takes the lower-case prefix and stays lower case throughout, because
          PingOne lower-cases a username on the way in and a caller that searched for the
          mixed-case form would find nothing.
        - An email is the username at the connection's email domain.

        A seeded person's GIVEN and FAMILY name are never prefixed. They carry a real name on
        purpose, so anything that displays, sorts or matches people by name is tested against
        names rather than against prefixed identifiers. Ownership is proved by the seed tag and
        the population, neither of which a human reads.

    .PARAMETER Key
        The bare key from the seed data.

    .PARAMETER Kind
        Which form to produce.

    .PARAMETER Connection
        The connection to take the prefix and email domain from. Defaults to the session's.

    .OUTPUTS
        System.String

    .EXAMPLE
        PS> Resolve-PingOneSeedName -Key 'All Staff' -Kind DisplayName

        DESCRIPTION: Names a group as the environment holds it
        OUTPUT: ZZ-TEST-All Staff
        USE CASE: Creating a group and finding it again at teardown

    .EXAMPLE
        PS> Resolve-PingOneSeedName -Key 'awhitfield' -Kind Username

        DESCRIPTION: Names a user as PingOne will store it
        OUTPUT: zz-test-awhitfield
        USE CASE: Creating a user, and every lookup of one afterwards

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
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DisplayName', 'Username', 'Email')]
        [string]$Kind,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-PingOneConnection }

    $prefix = (Get-PingOneSeedMarker -Prefix $Connection.Prefix).Prefix

    switch ($Kind) {
        'DisplayName' { return '{0}{1}' -f $prefix, $Key }
        'Username' { return ('{0}{1}' -f $prefix, $Key).ToLowerInvariant() }
        'Email' {
            $username = ('{0}{1}' -f $prefix, $Key).ToLowerInvariant()
            return '{0}@{1}' -f $username, $Connection.EmailDomain
        }
    }
}
