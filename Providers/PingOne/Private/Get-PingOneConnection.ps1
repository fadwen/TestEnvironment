function Get-PingOneConnection {
    <#
    .SYNOPSIS
        Returns the session's PingOne connection, or explains how to make one

    .DESCRIPTION
        Every function in this provider reaches the environment through here rather than
        reading module scope directly, so there is one message when nobody has connected and
        one place that knows what a connection has to carry.

        The connection holds two environment ids, and the distinction is the single thing most
        likely to waste somebody's afternoon. A worker application's token is issued by the
        environment the application lives in, which is often the Administrators environment,
        while the objects it manages live somewhere else. Authenticating against the target
        environment's token endpoint is refused with `invalid_client`, which reads exactly like
        a disabled application or a mistyped secret and is neither.

        So AuthEnvironmentId is where the token comes from and EnvironmentId is what gets
        seeded, and they are allowed to differ.

    .OUTPUTS
        System.Collections.Hashtable, the live connection.

    .EXAMPLE
        PS> $connection = Get-PingOneConnection

        DESCRIPTION: Fetches the connection every other function works through
        OUTPUT: The connection hashtable
        USE CASE: Called at the top of every function that reaches PingOne

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:PingOneConnection) {
        throw ('Not connected to PingOne. Run Connect-PingOneEnvironment -EnvironmentId ' +
            '<environment guid> -ClientId <worker app guid> -ClientSecret <secret> first, ' +
            'naming -AuthEnvironmentId as well if the worker application lives in a different ' +
            'environment from the one you are seeding.')
    }

    return $script:PingOneConnection
}
