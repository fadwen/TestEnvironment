function Get-AuthentikConnection {
    <#
    .SYNOPSIS
        Returns the active Authentik connection, or fails with the command that would create one

    .DESCRIPTION
        Every Authentik function reaches the instance through the connection that
        Connect-AuthentikEnvironment stored in module scope. Reading it through one accessor,
        rather than each function touching $script:AuthentikConnection itself, means the
        not-connected error is written once and names the fix, and the tests can substitute a
        connection by mocking a single command.

        An Authentik API token does not expire on a schedule the client can predict - it is
        either non-expiring or has an expiry the server enforces - so unlike the Okta accessor
        there is nothing to renew here. A 403 from a revoked token surfaces from the request
        that made it, with the server's own explanation.

    .PARAMETER AllowNone
        Return $null rather than throwing when nothing is connected. For callers that can
        answer the question without a connection, such as reading a credential record.

    .OUTPUTS
        System.Collections.Hashtable. The connection, as Connect-AuthentikEnvironment built it.

    .EXAMPLE
        PS> $connection = Get-AuthentikConnection

        DESCRIPTION: Reads the active connection
        OUTPUT: The connection hashtable, including the Authorization header
        USE CASE: The first line of every Authentik function that reaches the API

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [switch]$AllowNone
    )

    if (-not $script:AuthentikConnection) {
        if ($AllowNone) { return $null }
        throw ('Not connected to Authentik. Run Connect-TestEnvironment -Provider Authentik ' +
            '-BaseUrl https://<your-instance> -ApiToken <token> first.')
    }

    return $script:AuthentikConnection
}
