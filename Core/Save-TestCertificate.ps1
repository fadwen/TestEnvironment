function Save-TestCertificate {
    <#
    .SYNOPSIS
        Installs a generated certificate into the current user's store, with its private key

    .DESCRIPTION
        Exists as its own function for two reasons, and the second is the more important.

        The first is correctness. A certificate from CertificateRequest.CreateSelfSigned holds
        an EPHEMERAL private key - it lives in memory attached to that object and is not backed
        by a key container, so adding the object straight to the store persists only the public
        half. The result is a certificate with the right thumbprint that cannot sign anything,
        and the failure appears one connection later as "has no private key". Exporting to PFX
        and re-importing with PersistKeySet is what actually writes the key somewhere the store
        can reference it.

        The second is that this is the only part of the bootstrap that touches the machine
        rather than the tenant, and a unit test must be able to stop it. Inline
        X509Store calls cannot be mocked, so a suite exercising the bootstrap would silently
        install a certificate into the developer's personal store on every run - which is
        exactly what happened before this function existed, nine times.

    .PARAMETER Certificate
        The certificate to install, with its private key attached

    .OUTPUTS
        System.Boolean, true when the stored certificate has a usable private key.

    .EXAMPLE
        PS> Save-TestCertificate -Certificate $certificate

        DESCRIPTION: Installs the certificate into Cert:\CurrentUser\My
        OUTPUT: True
        USE CASE: Called by New-TestServiceApp after minting the key pair

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    if (-not $PSCmdlet.ShouldProcess("Cert:\CurrentUser\My", "Install certificate $($Certificate.Thumbprint)")) {
        return $false
    }

    # The password protects the PFX only while it is in memory between these two calls, and
    # the bytes are cleared immediately afterwards.
    $transitPassword = New-TestPassword -Length 48
    $pfx = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $transitPassword)

    try {
        $persistable = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfx, $transitPassword,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet)

        try {
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
            $store.Open('ReadWrite')
            try { $store.Add($persistable) } finally { $store.Close() }

            $usable = $persistable.HasPrivateKey
            Write-Verbose "Installed $($Certificate.Thumbprint) (private key usable: $usable)"
            return $usable
        }
        finally {
            $persistable.Dispose()
        }
    }
    finally {
        [Array]::Clear($pfx, 0, $pfx.Length)
    }
}
