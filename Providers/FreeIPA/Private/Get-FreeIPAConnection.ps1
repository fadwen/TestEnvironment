function Get-FreeIPAConnection {
    <#
    .SYNOPSIS
        Returns the active FreeIPA connection, or fails with the command that would create one

    .DESCRIPTION
        Every FreeIPA function reaches the realm through the connection that
        Connect-FreeIPAEnvironment stored in module scope. Reading it through one accessor,
        rather than each function touching $script:FreeIPAConnection itself, means the
        not-connected error is written once and names the fix, and the tests can substitute a
        connection by mocking a single command.

        The connection carries the HTTP client whose cookie jar holds the session, and the
        credential the session was opened with, because a FreeIPA session expires on idle and
        Invoke-FreeIPARequest opens a new one with that credential when it does.

    .PARAMETER AllowNone
        Return $null rather than throwing when nothing is connected. For callers that can
        answer the question without a connection, such as reading a credential record.

    .OUTPUTS
        System.Collections.Hashtable. The connection, as Connect-FreeIPAEnvironment built it.

    .EXAMPLE
        PS> $connection = Get-FreeIPAConnection

        DESCRIPTION: Reads the active connection
        OUTPUT: The connection hashtable, including the HTTP client and credential
        USE CASE: The first line of every FreeIPA function that reaches the API

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

    if (-not $script:FreeIPAConnection) {
        if ($AllowNone) { return $null }
        throw ('Not connected to FreeIPA. Run Connect-TestEnvironment -Provider FreeIPA ' +
            '-BaseUrl https://<your-server> -Credential <credential> first.')
    }

    return $script:FreeIPAConnection
}
