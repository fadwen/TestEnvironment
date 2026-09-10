function Get-AuthentikAccessToken {
    <#
    .SYNOPSIS
        Returns the token the session, or the stored service account, authenticates with

    .DESCRIPTION
        Authentik tokens are static bearer tokens rather than the short-lived access tokens
        Entra and Okta mint, so there is nothing to exchange: this returns the token in use.
        Connected with a service account, or given a credential record, it returns that
        account's token; connected with an API token it returns the API token. Either lets a
        script of your own call the API as the identity this module seeds with.

        Returned as a SecureString unless -AsPlainText is passed, for the same reason the
        other providers do: a token that lands in a transcript is a token to revoke.

    .PARAMETER CredentialPath
        A credential record to read the token from, instead of the session's.

    .PARAMETER BaseUrl
        The instance whose default record to read, when not connected.

    .PARAMETER VaultPassword
        The SecretStore password, when the token is in a vault whose password is not a default.

    .PARAMETER AsPlainText
        Return the token as a string.

    .OUTPUTS
        PSCustomObject with BaseUrl, Identity, Token, AuthType and CredentialPath; or with
        -AsPlainText, the token as a string.

    .EXAMPLE
        PS> $token = Get-AuthentikAccessToken -AsPlainText

        DESCRIPTION: Returns the session's token for a script that calls the API directly
        OUTPUT: The token string
        USE CASE: Reproducing a report against the API with the same identity

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path to a credential record, not a credential.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The token is already in memory; the SecureString is the safer return shape.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [string]$BaseUrl,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$AsPlainText
    )

    $connection = Get-AuthentikConnection -AllowNone

    $token = $null
    $identity = $null
    $authType = $null
    $resolvedPath = $null
    $resolvedUrl = $BaseUrl

    if ($CredentialPath -or ($connection -and $connection.AuthType -eq 'ServiceAccount') -or (-not $connection)) {
        if (-not $resolvedUrl -and $connection) { $resolvedUrl = $connection.BaseUrl }
        if (-not $resolvedUrl) { throw 'Not connected. Pass -BaseUrl, or -CredentialPath, or connect first.' }
        $existingPath = if ($CredentialPath) { $CredentialPath } elseif ($connection) { $connection.CredentialPath } else { $null }
        $resolvedPath = Get-AuthentikCredentialPath -BaseUrl $resolvedUrl -Path $existingPath
        $credential = Import-AuthentikCredential -Path $resolvedPath -VaultPassword $VaultPassword
        $token = $credential.Token
        $identity = $credential.Username
        $authType = 'ServiceAccount'
        $resolvedUrl = $credential.BaseUrl
    }
    else {
        $token = $connection.AuthorizationHeader -replace '^Bearer\s+', ''
        $identity = $connection.Identity
        $authType = $connection.AuthType
        $resolvedUrl = $connection.BaseUrl
    }

    if ($AsPlainText) { return $token }

    return [PSCustomObject]@{
        PSTypeName     = 'AuthentikAccessToken'
        BaseUrl        = $resolvedUrl
        Identity       = $identity
        AuthType       = $authType
        Token          = (ConvertTo-SecureString -String $token -AsPlainText -Force)
        CredentialPath = $resolvedPath
    }
}
