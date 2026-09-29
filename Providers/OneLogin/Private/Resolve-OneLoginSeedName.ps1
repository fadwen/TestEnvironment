function Resolve-OneLoginSeedName {
    <#
    .SYNOPSIS
        Turns a seed-file key into the name the object carries in the account

    .DESCRIPTION
        The seed files hold bare keys and names - 'all-staff', 'Expenses Web', 'awhitfield' - and
        the account holds prefixed ones. This is the one place the two are related, so every step
        names an object the same way and teardown and verification find what the seed made.

        Three forms:

        - A display name takes the prefix as written: 'All Staff' becomes 'ZZ-TEST-All Staff'.
          Roles, groups, apps and mappings all use this.
        - A username takes the prefix lower-cased and stays lower case throughout, so a lookup
          by username never depends on how the account folds case.
        - An email is the username at the connection's email domain.

        A seeded person's first and last name are never prefixed. They carry a real name on
        purpose, so anything that displays, sorts or matches people by name is tested against
        names rather than against prefixed identifiers. Ownership is proved by the seed tag in
        the user's custom field and the prefix on the username, neither of which a person reads.

    .PARAMETER Key
        The bare key or name from the seed data.

    .PARAMETER Kind
        Which form to produce.

    .PARAMETER Connection
        The connection to take the prefix and email domain from. Defaults to the session's.

    .OUTPUTS
        System.String

    .EXAMPLE
        PS> Resolve-OneLoginSeedName -Key 'All Staff' -Kind DisplayName

        DESCRIPTION: Names a role as the account holds it
        OUTPUT: ZZ-TEST-All Staff
        USE CASE: Creating a role and finding it again at teardown

    .EXAMPLE
        PS> Resolve-OneLoginSeedName -Key 'awhitfield' -Kind Username

        DESCRIPTION: Names a user
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

    if (-not $Connection) { $Connection = Get-OneLoginConnection }

    $prefix = (Get-OneLoginSeedMarker -Prefix $Connection.Prefix).Prefix

    switch ($Kind) {
        'DisplayName' { return '{0}{1}' -f $prefix, $Key }
        'Username' { return ('{0}{1}' -f $prefix, $Key).ToLowerInvariant() }
        'Email' {
            $username = ('{0}{1}' -f $prefix, $Key).ToLowerInvariant()
            return '{0}@{1}' -f $username, $Connection.EmailDomain
        }
    }
}
