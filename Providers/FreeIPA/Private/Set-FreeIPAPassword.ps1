function Set-FreeIPAPassword {
    <#
    .SYNOPSIS
        Changes a user's password as that user, through the endpoint that needs no session

    .DESCRIPTION
        Any password an administrator sets in FreeIPA is expired the moment it is set: the user
        has to change it before it can be used. The change-password endpoint is how that
        happens without a session - it takes the login, the old password and the new one - and
        it is the only way to end up with a password that is current rather than
        must-change. The seed uses it three times over: to make the service account's password
        current after the bootstrap set it, to rotate that password when the realm's policy
        has expired it, and to give a seeded user whose row says 'Current' a password that is.

        The result comes back in headers rather than a status: X-IPA-Pwchange-Result is 'ok',
        'invalid-password', 'policy-error' or 'error', and a policy failure explains itself in
        X-IPA-Pwchange-Policy-Error. Anything but 'ok' is thrown with that explanation, because
        a caller that carried on would then store or report a password that does not work.

    .PARAMETER Connection
        The connection whose client to send through. Only the client and base URL are used;
        the change is authenticated by the old password, not by the session.

    .PARAMETER Username
        The login whose password changes.

    .PARAMETER OldPassword
        The current password.

    .PARAMETER NewPassword
        The new password.

    .OUTPUTS
        None.

    .EXAMPLE
        PS> Set-FreeIPAPassword -Connection $connection -Username 'zz-test-automation' -OldPassword $random -NewPassword $fresh

        DESCRIPTION: Makes an admin-set password current
        OUTPUT: None; throws with the policy error if the realm refuses
        USE CASE: The bootstrap, right after creating the service account

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'OldPassword',
        Justification = 'Already in memory as text from the record or the API; sent to the server as a form field.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NewPassword',
        Justification = 'Generated or decrypted in memory moments earlier; sent to the server as a form field.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
        Justification = 'The endpoint takes a login, the old password and the new one as form fields; there is no credential object to pass.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Connection,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OldPassword,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Username, 'Change the password')) { return }

    $response = Send-FreeIPAHttpRequest -Connection $Connection -Path '/ipa/session/change_password' `
        -Form @{ user = $Username; old_password = $OldPassword; new_password = $NewPassword } -Accept 'text/plain'

    $result = 'error'
    if ($response.Headers.ContainsKey('X-IPA-Pwchange-Result')) { $result = [string]$response.Headers['X-IPA-Pwchange-Result'] }

    if ($result -eq 'ok') {
        Write-Verbose "Changed the password of $Username"
        return
    }

    $detail = ''
    if ($response.Headers.ContainsKey('X-IPA-Pwchange-Policy-Error')) { $detail = ': ' + [string]$response.Headers['X-IPA-Pwchange-Policy-Error'] }
    elseif (-not [string]::IsNullOrWhiteSpace($response.Body)) {
        $firstLine = @(($response.Body -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        $detail = ': ' + ($firstLine -join '')
    }
    throw "FreeIPA refused the password change for $Username ($result)$detail"
}
