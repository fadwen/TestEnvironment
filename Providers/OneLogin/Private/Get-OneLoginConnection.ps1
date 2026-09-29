function Get-OneLoginConnection {
    <#
    .SYNOPSIS
        Returns the session's OneLogin connection, or explains how to make one

    .DESCRIPTION
        Every function in this provider reaches the account through here rather than reading
        module scope directly, so there is one message when nobody has connected and one place
        that knows what a connection has to carry.

        The connection holds the account's subdomain, the API credential's client id and secret,
        the token and its expiry, and the Prefix and EmailDomain everything the seed creates is
        named with. Teardown keys off the prefix, so setting it once at connect time removes the
        failure mode where an account is seeded under one prefix and torn down under another.

    .OUTPUTS
        System.Collections.Hashtable, the live connection.

    .EXAMPLE
        PS> $connection = Get-OneLoginConnection

        DESCRIPTION: Fetches the connection every other function works through
        OUTPUT: The connection hashtable
        USE CASE: Called at the top of every function that reaches OneLogin

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:OneLoginConnection) {
        throw ('Not connected to OneLogin. Run Connect-TestEnvironment -Provider OneLogin -Subdomain <name> ' +
            '-ClientId <id> -ClientSecret <secret> first, or -UseStoredCredential once a secret has been saved.')
    }

    return $script:OneLoginConnection
}
