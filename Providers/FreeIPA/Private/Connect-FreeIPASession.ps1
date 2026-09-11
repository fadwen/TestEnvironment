function Connect-FreeIPASession {
    <#
    .SYNOPSIS
        Logs a connection's client in with its credential and reports how the server answered

    .DESCRIPTION
        FreeIPA's password login is a form post that sets a session cookie in the client's
        jar on success and, on failure, answers 401 with the reason in the
        X-IPA-Rejection-Reason header: 'invalid-password', 'password-expired',
        'krbprincipal-expired', 'user-locked' or 'denied'. Those reasons are what the callers
        act on - a connect that meets 'password-expired' on the service account rotates the
        password; on a bootstrap credential it explains - so this returns them rather than
        throwing, and throws only when the server could not be reached or answered something
        that is neither success nor a rejection.

    .PARAMETER Connection
        The connection, carrying the client, the login and the password.

    .OUTPUTS
        PSCustomObject with Success and Reason.

    .EXAMPLE
        PS> $login = Connect-FreeIPASession -Connection $candidate

        DESCRIPTION: Opens a session for a connection being built
        OUTPUT: Success true, or Success false with the server's reason
        USE CASE: Connect-FreeIPAEnvironment, and Invoke-FreeIPARequest when a session has expired

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Connection
    )

    $response = Send-FreeIPAHttpRequest -Connection $Connection -Path '/ipa/session/login_password' `
        -Form @{ user = $Connection.Username; password = $Connection.Password } -Accept 'text/plain'

    if ($response.StatusCode -eq 200) {
        return [PSCustomObject]@{ Success = $true; Reason = $null }
    }

    if ($response.StatusCode -eq 401) {
        $reason = 'denied'
        if ($response.Headers.ContainsKey('X-IPA-Rejection-Reason')) { $reason = [string]$response.Headers['X-IPA-Rejection-Reason'] }
        return [PSCustomObject]@{ Success = $false; Reason = $reason }
    }

    $firstLine = @(($response.Body -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    throw "FreeIPA login at $($Connection.BaseUrl) answered HTTP $($response.StatusCode): $($firstLine -join '')"
}
