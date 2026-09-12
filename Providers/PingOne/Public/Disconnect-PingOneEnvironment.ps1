function Disconnect-PingOneEnvironment {
    <#
    .SYNOPSIS
        Clears the session's PingOne connection and the token it holds

    .DESCRIPTION
        Removes the connection from module scope so that a later call fails with "not
        connected" rather than reaching an environment the caller has stopped thinking about.

        The access token and the worker secret go with it. The secret is a SecureString, so it
        is disposed rather than merely dereferenced: dropping the reference leaves the value in
        memory until the garbage collector gets to it, and disposing zeroes it now.

        Nothing in the environment changes. This is a local operation, and there is no PingOne
        call to revoke a client credentials token.

    .EXAMPLE
        PS> Disconnect-TestEnvironment

        DESCRIPTION: Ends the session's connection
        OUTPUT: None
        USE CASE: Finishing with one environment before connecting to another

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        Connect-PingOneEnvironment
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not $script:PingOneConnection) {
        Write-Verbose 'No PingOne connection to clear.'
        return
    }

    $environmentId = $script:PingOneConnection.EnvironmentId

    if ($script:PingOneConnection.ClientSecret -is [System.Security.SecureString]) {
        $script:PingOneConnection.ClientSecret.Dispose()
    }
    $script:PingOneConnection.AccessToken = $null

    Remove-Variable -Name PingOneConnection -Scope Script -ErrorAction SilentlyContinue

    Write-Verbose "Disconnected from PingOne environment $environmentId"
}
