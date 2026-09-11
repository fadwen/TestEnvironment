function Get-FreeIPAAccessToken {
    <#
    .SYNOPSIS
        Returns the session cookie the connection authenticates with

    .DESCRIPTION
        FreeIPA has no bearer token. A password login sets an ipa_session cookie, and every
        API call carries that cookie and a Referer header naming the server. This returns the
        cookie the active connection holds, so a script of your own can call the JSON-RPC
        endpoint as the identity this module seeds with, by sending it as
        'Cookie: ipa_session=<value>' with 'Referer: <server>/ipa'. The session expires on
        idle, so a cookie taken now is good for minutes rather than days.

        Returned as a SecureString unless -AsPlainText is passed, for the same reason the
        other providers do: a session that lands in a transcript is a session to end.

    .PARAMETER AsPlainText
        Return the cookie value as a string.

    .OUTPUTS
        PSCustomObject with BaseUrl, Identity, AuthType, CookieName, Referer and Token; or
        with -AsPlainText, the cookie value as a string.

    .EXAMPLE
        PS> $session = Get-FreeIPAAccessToken -AsPlainText

        DESCRIPTION: Returns the session cookie for a script that calls the API directly
        OUTPUT: The cookie value
        USE CASE: Reproducing a report against the API with the same identity

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The cookie is already in memory; the SecureString is the safer return shape.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [Parameter()]
        [switch]$AsPlainText
    )

    $connection = Get-FreeIPAConnection

    $cookieValue = $null
    if ($connection.Cookies) {
        foreach ($cookie in $connection.Cookies.GetCookies([uri]$connection.BaseUrl)) {
            if ($cookie.Name -eq 'ipa_session') { $cookieValue = $cookie.Value }
        }
    }
    if ([string]::IsNullOrWhiteSpace($cookieValue)) {
        throw 'The connection holds no session cookie. Reconnect with Connect-TestEnvironment.'
    }

    if ($AsPlainText) { return $cookieValue }

    return [PSCustomObject]@{
        PSTypeName = 'FreeIPAAccessToken'
        BaseUrl    = $connection.BaseUrl
        Identity   = $connection.Identity
        AuthType   = $connection.AuthType
        CookieName = 'ipa_session'
        Referer    = '{0}/ipa' -f $connection.BaseUrl
        Token      = (ConvertTo-SecureString -String $cookieValue -AsPlainText -Force)
    }
}
