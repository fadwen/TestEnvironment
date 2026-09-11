function New-FreeIPACertificateRequest {
    <#
    .SYNOPSIS
        Builds a PKCS#10 certificate signing request with in-box .NET, and returns it as PEM

    .DESCRIPTION
        The realm's CA signs whatever the seed asks it to, and it asks with a request signed
        by a key generated here and thrown away: nothing ever needs to use the certificates,
        only to see them on the entries and in the CA. The request carries the subject the
        realm demands - the login or the host name as the common name, the realm as the
        organisation - and the subject alternative names a row asks for, which the realm
        checks against the principal.

        System.Security.Cryptography.X509Certificates.CertificateRequest is in .NET Framework
        4.7.2 and every .NET Core, so both editions build the request without a module and
        without openssl. A machine older than that gets a plain error rather than a type
        resolution failure.

    .PARAMETER Subject
        The distinguished name, for example CN=jnino,O=IPA.EXAMPLE.COM.

    .PARAMETER DnsName
        DNS names for the subject alternative name extension.

    .PARAMETER EmailAddress
        Email addresses for the subject alternative name extension.

    .PARAMETER KeySize
        RSA key size. Defaults to 2048.

    .OUTPUTS
        System.String. The request as PEM, with the BEGIN and END lines.

    .EXAMPLE
        PS> New-FreeIPACertificateRequest -Subject 'CN=zz-test-web01.ipa.example.com,O=IPA.EXAMPLE.COM' -DnsName 'zz-test-web01.ipa.example.com'

        DESCRIPTION: Builds a request for a service certificate
        OUTPUT: The PEM text
        USE CASE: Handed to cert_request by New-FreeIPACertificate

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a request in memory and changes nothing; the key is discarded before it returns.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subject,

        [Parameter()]
        [string[]]$DnsName = @(),

        [Parameter()]
        [string[]]$EmailAddress = @(),

        [Parameter()]
        [ValidateSet(2048, 3072, 4096)]
        [int]$KeySize = 2048
    )

    if (-not ('System.Security.Cryptography.X509Certificates.CertificateRequest' -as [type])) {
        throw 'Building a certificate request needs .NET Framework 4.7.2 or later, or PowerShell 7.'
    }

    $rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
    try {
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $Subject, $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        $names = @($DnsName | Where-Object { $_ }) + @($EmailAddress | Where-Object { $_ })
        if ($names.Count -gt 0) {
            $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
            foreach ($name in @($DnsName | Where-Object { $_ })) { $san.AddDnsName($name) }
            foreach ($address in @($EmailAddress | Where-Object { $_ })) { $san.AddEmailAddress($address) }
            $request.CertificateExtensions.Add($san.Build())
        }

        $der = $request.CreateSigningRequest()
    }
    finally {
        $rsa.Dispose()
    }

    $body = [Convert]::ToBase64String($der, [Base64FormattingOptions]::InsertLineBreaks)
    return "-----BEGIN CERTIFICATE REQUEST-----`n$body`n-----END CERTIFICATE REQUEST-----`n"
}
