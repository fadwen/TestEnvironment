#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The client assertion is the credential. If it is wrong, Entra says AADSTS700027 or
    AADSTS50027 and names neither the claim nor the header that caused it, so these assertions
    check the things those two errors actually mean.

    The signature test verifies against the certificate's own public key rather than against a
    recorded expected value. A recorded signature would only prove the code still does what it
    did, which is not the same as proving Entra will accept it.

    A self-signed certificate is generated in memory for the suite. Nothing reaches a tenant
    and no certificate is written to the store.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force

    # Built rather than imported: the suite must not depend on a certificate existing in
    # anybody's store, and this one never leaves the process.
    $script:Rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=EntraEnvironment-UnitTest',
        $script:Rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $script:Certificate = $request.CreateSelfSigned(
        [DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(30))

    $script:ClientId = '895bcc2f-ad2f-4ec4-8dfe-310251b5e1a8'
    $script:TenantId = 'b818de68-9112-40b3-adc2-6838048cd611'
}

AfterAll {
    if ($script:Certificate) { $script:Certificate.Dispose() }
    if ($script:Rsa) { $script:Rsa.Dispose() }
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraClientAssertion' -Tag 'Unit' {

    BeforeAll {
        $script:Assertion = InModuleScope TestEnvironment -Parameters @{
            Certificate = $script:Certificate; ClientId = $script:ClientId; TenantId = $script:TenantId
        } {
            param($Certificate, $ClientId, $TenantId)
            New-EntraClientAssertion -Certificate $Certificate -ClientId $ClientId -TenantId $TenantId
        }

        $script:Segments = $script:Assertion.Split('.')
        $script:Header = InModuleScope TestEnvironment -Parameters @{ Segment = $script:Segments[0] } {
            param($Segment)
            [System.Text.Encoding]::UTF8.GetString((ConvertFrom-TestBase64Url -Text $Segment)) | ConvertFrom-Json
        }
        $script:Claims = InModuleScope TestEnvironment -Parameters @{ Segment = $script:Segments[1] } {
            param($Segment)
            [System.Text.Encoding]::UTF8.GetString((ConvertFrom-TestBase64Url -Text $Segment)) | ConvertFrom-Json
        }
    }

    It 'produces three dot-separated segments' {
        $script:Segments.Count | Should-Be 3
    }

    It 'declares RS256, which is the only algorithm Entra accepts here' {
        $script:Header.alg | Should-Be 'RS256'
        $script:Header.typ | Should-Be 'JWT'
    }

    It 'sends x5t as the base64url of the thumbprint BYTES, not of its hex text' {
        # The mistake that produces AADSTS700027. Base64url-encoding the hex string is the
        # obvious wrong thing to do and yields a valid-looking token Entra cannot match to a
        # registered key.
        $expected = [Convert]::ToBase64String($script:Certificate.GetCertHash()).
            TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $script:Header.x5t | Should-Be $expected

        $hexEncoded = [Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes($script:Certificate.Thumbprint)).
            TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $script:Header.x5t | Should-NotBe $hexEncoded
    }

    It 'addresses the v2.0 token endpoint for the specific tenant' {
        # A v1.0 audience, or the common endpoint, is rejected with AADSTS50027 for a token
        # that is otherwise entirely valid.
        $script:Claims.aud | Should-Be "https://login.microsoftonline.com/$script:TenantId/oauth2/v2.0/token"
        $script:Claims.aud | Should-NotMatchString '/common/'
        $script:Claims.aud | Should-NotMatchString 'oauth2/token$'
    }

    It 'uses the client id as both issuer and subject' {
        $script:Claims.iss | Should-Be $script:ClientId
        $script:Claims.sub | Should-Be $script:ClientId
    }

    It 'carries a unique jti on every call' {
        $second = InModuleScope TestEnvironment -Parameters @{
            Certificate = $script:Certificate; ClientId = $script:ClientId; TenantId = $script:TenantId
        } {
            param($Certificate, $ClientId, $TenantId)
            New-EntraClientAssertion -Certificate $Certificate -ClientId $ClientId -TenantId $TenantId
        }
        $secondClaims = InModuleScope TestEnvironment -Parameters @{ Segment = $second.Split('.')[1] } {
            param($Segment)
            [System.Text.Encoding]::UTF8.GetString((ConvertFrom-TestBase64Url -Text $Segment)) | ConvertFrom-Json
        }

        $secondClaims.jti | Should-NotBe $script:Claims.jti
    }

    It 'backdates nbf so a fast local clock does not invalidate it' {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $script:Claims.nbf | Should-BeLessThan $now
    }

    It 'expires within the ten minutes Entra permits' {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $script:Claims.exp | Should-BeGreaterThan $now
        ($script:Claims.exp - $now) | Should-BeLessThanOrEqual 600
    }

    It 'signs the header and claims, and the signature verifies against the public key' {
        # The assertion that matters. It proves Entra can verify what was produced, rather
        # than proving the code is unchanged.
        $signingInput = [System.Text.Encoding]::ASCII.GetBytes("$($script:Segments[0]).$($script:Segments[1])")
        $signature = InModuleScope TestEnvironment -Parameters @{ Segment = $script:Segments[2] } {
            param($Segment)
            ConvertFrom-TestBase64Url -Text $Segment
        }

        $publicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($script:Certificate)
        try {
            $verified = $publicKey.VerifyData(
                $signingInput, $signature,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $verified | Should-BeTrue
        }
        finally {
            $publicKey.Dispose()
        }
    }

    It 'does not verify when the signed content is altered' {
        # Guards against a signature that verifies for the wrong reason, such as one computed
        # over a constant.
        $tampered = [System.Text.Encoding]::ASCII.GetBytes("$($script:Segments[0]).$($script:Segments[1])x")
        $signature = InModuleScope TestEnvironment -Parameters @{ Segment = $script:Segments[2] } {
            param($Segment)
            ConvertFrom-TestBase64Url -Text $Segment
        }

        $publicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($script:Certificate)
        try {
            $publicKey.VerifyData(
                $tampered, $signature,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should-BeFalse
        }
        finally {
            $publicKey.Dispose()
        }
    }
}
