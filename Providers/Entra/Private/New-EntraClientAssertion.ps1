function New-EntraClientAssertion {
    <#
    .SYNOPSIS
        Builds and signs the RS256 JWT Entra accepts in place of a client secret

    .DESCRIPTION
        Certificate credentials on a confidential client work by private_key_jwt: the caller
        signs a short-lived assertion with the certificate's private key, and Entra verifies
        it against the public key already registered on the application. Nothing secret ever
        crosses the wire, which is the whole reason to prefer this over a client secret.

        Two details are worth knowing because both fail obscurely.

        The 'x5t' header is how Entra decides which registered key to verify against, and it
        is the base64url encoding of the certificate's SHA-1 hash BYTES. The thumbprint that
        the certificate store shows is that same hash rendered as hex, so it has to be decoded
        back to bytes first. Base64url-encoding the hex string instead produces a well-formed
        assertion that Entra rejects with AADSTS700027 - it cannot find a key matching the
        thumbprint you did not send.

        The 'aud' claim must be the v2.0 token endpoint for the specific tenant. A v1.0
        audience, or the common endpoint, is rejected with AADSTS50027 for a token that is
        otherwise entirely valid.

        Lifetime is deliberately short. The assertion is single use in practice and Entra
        allows up to ten minutes; five is enough to absorb ordinary clock skew without
        leaving a usable credential lying around in a transcript. 'nbf' is backdated by
        thirty seconds for the same reason - a workstation clock a few seconds ahead of
        Microsoft's is common, and an assertion not yet valid is refused outright.

    .PARAMETER Certificate
        The signing certificate, which must hold an RSA private key

    .PARAMETER ClientId
        Application (client) ID, used as both issuer and subject

    .PARAMETER TenantId
        Directory (tenant) ID, which selects the token endpoint named in the audience

    .PARAMETER LifetimeMinutes
        How long the assertion stays valid

    .OUTPUTS
        System.String. The signed JWT, as three base64url segments separated by dots.

    .EXAMPLE
        PS> New-EntraClientAssertion -Certificate $cert -ClientId $appId -TenantId $tenant

        DESCRIPTION: Signs an assertion for the client credentials grant
        OUTPUT: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsIng1dCI6Ii4uLiJ9.eyJhdWQiOiJodHRwczov...
        USE CASE: Called by Get-EntraAccessToken on every token request

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Changes no state. It computes a value in memory and returns it; the New verb describes constructing an object, not modifying anything.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$LifetimeMinutes = 5
    )

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if (-not $rsa) {
        Write-Error "Certificate $($Certificate.Thumbprint) exposes no RSA private key to sign with." -ErrorAction Stop
        return
    }

    # GetCertHash() returns the SHA-1 hash as bytes. That is the same value the store renders
    # as the hex thumbprint, and it is the bytes Entra wants base64url-encoded here.
    $x5t = ConvertTo-TestBase64Url -Bytes $Certificate.GetCertHash()

    $header = [ordered]@{
        alg = 'RS256'
        typ = 'JWT'
        x5t = $x5t
    }

    $now = [DateTimeOffset]::UtcNow
    $claims = [ordered]@{
        aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.AddSeconds(-30).ToUnixTimeSeconds()
        exp = $now.AddMinutes($LifetimeMinutes).ToUnixTimeSeconds()
        iat = $now.ToUnixTimeSeconds()
    }

    # -Compress matters beyond neatness: the signature covers these exact bytes, so any
    # whitespace ConvertTo-Json would otherwise insert becomes part of what was signed.
    $headerSegment = ConvertTo-TestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))
    $claimsSegment = ConvertTo-TestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))

    $signingInput = "$headerSegment.$claimsSegment"
    $signature = $rsa.SignData(
        [System.Text.Encoding]::ASCII.GetBytes($signingInput),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    return "$signingInput.$(ConvertTo-TestBase64Url -Bytes $signature)"
}
