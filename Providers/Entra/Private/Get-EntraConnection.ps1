function Get-EntraConnection {
    <#
    .SYNOPSIS
        Returns the active connection, or fails with the command that creates one

    .DESCRIPTION
        Every function in this module reaches Graph through the connection that
        Connect-EntraEnvironment stores. Centralising the "are we connected" check means
        the failure names the fix once, rather than each caller producing its own version of
        a null reference several frames deeper.

    .OUTPUTS
        System.Collections.Hashtable

    .EXAMPLE
        PS> $connection = Get-EntraConnection

        DESCRIPTION: Retrieves the connection established by Connect-EntraEnvironment
        OUTPUT: The connection hashtable
        USE CASE: Called at the top of every function that talks to Graph

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:EntraConnection) {
        Write-Error ("Not connected. Run Connect-EntraEnvironment -TenantId <id> -ClientId <id> " +
            "-CertificateThumbprint <thumbprint> first.") -ErrorAction Stop
        return
    }

    return $script:EntraConnection
}
