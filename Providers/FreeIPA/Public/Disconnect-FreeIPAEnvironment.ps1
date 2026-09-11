function Disconnect-FreeIPAEnvironment {
    <#
    .SYNOPSIS
        Clears the stored FreeIPA connection

    .DESCRIPTION
        Drops the connection Connect-FreeIPAEnvironment stored, and with it the password and
        the session cookie held in memory, and disposes the HTTP client. Nothing is changed
        on the server: the session simply lapses, and the service account outlives the session
        by design so that the next session can connect with it again.

        Silent when nothing is connected, so a script can disconnect unconditionally.

    .PARAMETER PassThru
        Returns a result naming the server that was disconnected.

    .OUTPUTS
        PSCustomObject with BaseUrl and Identity, when -PassThru is supplied.

    .EXAMPLE
        PS> Disconnect-FreeIPAEnvironment

        DESCRIPTION: Clears the connection
        OUTPUT: None
        USE CASE: The end of a session, or before connecting to a different realm

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

    $connection = Get-FreeIPAConnection -AllowNone
    if (-not $connection) {
        Write-Verbose 'No FreeIPA connection to clear.'
        return
    }

    if ($PSCmdlet.ShouldProcess($connection.BaseUrl, 'Clear the stored credential')) {
        $script:FreeIPAConnection = $null
        if ($connection.Client) {
            try { $connection.Client.Dispose() } catch { Write-Verbose "The HTTP client did not dispose cleanly: $($_.Exception.Message)" }
        }
        Write-Verbose "Disconnected from $($connection.BaseUrl)"

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName = 'FreeIPADisconnectResult'
                BaseUrl    = $connection.BaseUrl
                Identity   = $connection.Identity
            }
        }
    }
}
