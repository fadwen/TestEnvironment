function Disconnect-ADEnvironment {
    <#
    .SYNOPSIS
        Clears the recorded Active Directory connection

    .DESCRIPTION
        Forgets the domain this session was working against. There is no session to close and no
        token to revoke - AD is reached with the caller's own Windows identity - so this exists
        for the same reason the connection does: every later command reads the recorded domain
        rather than re-detecting one, and being able to clear it deliberately is what stops a
        long-running session from carrying a stale answer.

        The RSAT modules stay imported. They belong to the session rather than to this module,
        and unloading something the caller may be using themselves would be a surprise.

    .PARAMETER PassThru
        Returns what was disconnected

    .OUTPUTS
        ADEnvironmentDisconnectResult when -PassThru is supplied

    .EXAMPLE
        PS> Disconnect-TestEnvironment

        DESCRIPTION: Forgets the connected domain
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: Before connecting to a different domain in the same session

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('ADEnvironmentDisconnectResult')]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    $previous = $script:ADConnection

    if (-not $previous) {
        Write-Verbose 'No Active Directory connection to clear'
        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName   = 'ADEnvironmentDisconnectResult'
                Disconnected = $false
                DNSName      = $null
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($previous.DNSName, 'Clear the recorded Active Directory connection')) {
        $script:ADConnection = $null
        Write-Verbose "Disconnected from $($previous.DNSName)"

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName   = 'ADEnvironmentDisconnectResult'
                Disconnected = $true
                DNSName      = $previous.DNSName
            }
        }
    }
}
