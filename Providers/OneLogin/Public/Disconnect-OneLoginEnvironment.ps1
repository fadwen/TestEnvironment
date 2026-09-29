function Disconnect-OneLoginEnvironment {
    <#
    .SYNOPSIS
        Revokes the session's OneLogin token and clears the connection

    .DESCRIPTION
        Removes the connection from module scope so that a later call fails with "not connected"
        rather than reaching an account the caller has stopped thinking about.

        The token is revoked first, at /auth/oauth2/revoke, because a OneLogin token lives ten
        hours and would otherwise stay valid long after the session that asked for it. The
        revocation is best effort: a network failure or a token that already expired is not a
        reason to keep a connection the caller asked to drop, so it is reported verbosely and the
        connection is cleared regardless.

        The secret is a SecureString, so it is disposed rather than merely dereferenced: dropping
        the reference leaves the value in memory until the garbage collector gets to it, and
        disposing zeroes it now.

        Nothing in the account changes.

    .EXAMPLE
        PS> Disconnect-TestEnvironment

        DESCRIPTION: Ends the session's connection
        OUTPUT: None
        USE CASE: Finishing with one account before connecting to another

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        Connect-OneLoginEnvironment
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not $script:OneLoginConnection) {
        Write-Verbose 'No OneLogin connection to clear.'
        return
    }

    $connection = $script:OneLoginConnection
    $subdomain = $connection.Subdomain

    if ($connection.AccessToken) {
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($connection.ClientSecret)
            $pair = '{0}:{1}' -f $connection.ClientId, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
            $pair = $null
            $null = Invoke-TestWebRequest -Method POST -Uri ('https://{0}/auth/oauth2/revoke' -f $connection.ApiHost) `
                -Headers @{ Authorization = "Basic $basic" } -Body @{ access_token = $connection.AccessToken }
            Write-Verbose 'Revoked the OneLogin access token'
        }
        catch {
            Write-Verbose "Could not revoke the OneLogin access token: $($_.Exception.Message)"
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $basic = $null
        }
    }

    $connection.AccessToken = $null
    if ($connection.ClientSecret -is [System.Security.SecureString]) { $connection.ClientSecret.Dispose() }

    Remove-Variable -Name OneLoginConnection -Scope Script -ErrorAction SilentlyContinue

    Write-Verbose "Disconnected from OneLogin account $subdomain"
}
