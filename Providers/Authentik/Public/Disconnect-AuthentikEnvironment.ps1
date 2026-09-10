function Disconnect-AuthentikEnvironment {
    <#
    .SYNOPSIS
        Clears the stored Authentik connection

    .DESCRIPTION
        Drops the connection Connect-AuthentikEnvironment stored, and with it the bearer
        token held in memory. Nothing is revoked on the instance: an API token or a service
        account token outlives the session by design, so that the next session can connect
        with it again.

        Silent when nothing is connected, so a script can disconnect unconditionally.

    .PARAMETER PassThru
        Returns a result naming the instance that was disconnected.

    .OUTPUTS
        PSCustomObject with BaseUrl and Identity, when -PassThru is supplied.

    .EXAMPLE
        PS> Disconnect-AuthentikEnvironment

        DESCRIPTION: Clears the connection
        OUTPUT: None
        USE CASE: The end of a session, or before connecting to a different instance

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection -AllowNone
    if (-not $connection) {
        Write-Verbose 'No Authentik connection to clear.'
        return
    }

    if ($PSCmdlet.ShouldProcess($connection.BaseUrl, 'Clear the stored credential')) {
        $script:AuthentikConnection = $null
        Write-Verbose "Disconnected from $($connection.BaseUrl)"

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName = 'AuthentikDisconnectResult'
                BaseUrl    = $connection.BaseUrl
                Identity   = $connection.Identity
            }
        }
    }
}
