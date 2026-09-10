function Test-ADTestAdministrator {
    <#
    .SYNOPSIS
        Reports whether the current session is running elevated.

    .DESCRIPTION
        Wraps the WindowsPrincipal check used by the SecretStore vault functions. An
        AllUsers scope vault can only be registered, and only unregistered, from an
        elevated session, so both the create and the remove path need this answer.

        It exists as a function rather than being inlined at each call site because it
        previously was inlined: New-ADTestSecretVault checked elevation and branched on
        it, Remove-ADTestSecretVault did not check at all, and the -GlobalVault switch on
        the remove side was silently inert as a result.

        Returns $false rather than throwing when the identity cannot be read, so a caller
        on a non-Windows host degrades to the unelevated path instead of failing.

    .EXAMPLE
        if (Test-ADTestAdministrator) { $vaultParams.Scope = 'AllUsers' }

    .OUTPUTS
        System.Boolean

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

        return $principal.IsInRole($adminRole)
    }
    catch {
        Write-Verbose "Could not determine admin status: $($_.Exception.Message)"
        return $false
    }
}
