function Disconnect-EntraEnvironment {
    <#
    .SYNOPSIS
        Clears the stored connection and its access token

    .DESCRIPTION
        Drops the module-scoped connection, including the cached bearer token and the
        reference to the signing certificate.

        Disconnecting when nothing is connected is a no-op rather than an error. A cleanup
        block that has to test whether it needs to clean up is a cleanup block that gets
        skipped, so this is safe to call unconditionally in a finally.

        Note what this does not do: the certificate itself is untouched, because the module
        did not create it and removing a credential the caller supplied is not cleanup, it
        is damage. Nothing already seeded in the tenant is affected either -
        Remove-EntraEnvironment is the command for that.

    .PARAMETER PassThru
        Returns a summary of the connection that was cleared

    .OUTPUTS
        EntraDisconnectResult when -PassThru is supplied

    .EXAMPLE
        PS> Disconnect-EntraEnvironment

        DESCRIPTION: Clears the credential without unloading the module
        OUTPUT: None
        USE CASE: Ending a session, or switching to a different tenant

    .EXAMPLE
        PS> Disconnect-EntraEnvironment -WhatIf

        DESCRIPTION: Reports what would be cleared and clears nothing
        OUTPUT: What if: Performing the operation "Clear stored connection" on target "Contoso"
        USE CASE: Confirming which tenant the session is pointed at

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraDisconnectResult')]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    if (-not $script:EntraConnection) {
        Write-Verbose "No connection to clear."
        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName = 'EntraDisconnectResult'
                Cleared    = $false
                TenantId   = $null
                TenantName = $null
            }
        }
        return
    }

    $tenantId = $script:EntraConnection.TenantId
    $tenantName = $script:EntraConnection.TenantName
    $target = if ($tenantName) { $tenantName } else { $tenantId }

    if ($PSCmdlet.ShouldProcess($target, 'Clear stored connection')) {
        $script:EntraConnection = $null
        Write-Verbose "Cleared the connection to $target"

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName = 'EntraDisconnectResult'
                Cleared    = $true
                TenantId   = $tenantId
                TenantName = $tenantName
            }
        }
        return
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName = 'EntraDisconnectResult'
            Cleared    = $false
            TenantId   = $tenantId
            TenantName = $tenantName
        }
    }
}
