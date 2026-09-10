function Get-TestCertificate {
    <#
    .SYNOPSIS
        Resolves a signing certificate from a thumbprint, a path, or an object

    .DESCRIPTION
        Certificates arrive three ways - a thumbprint, a PFX, or an object - and they all end up
        here, so the rules about what makes a certificate usable live in one place.

        A certificate is usable for app-only authentication only if it carries a private
        key that can actually sign. Three things go wrong in practice and all three are
        checked, because each produces a failure much later and much less clearly:

        - The public half is installed but the private key is not. Get-ChildItem finds the
          certificate, everything looks right, and signing throws a null reference.
        - The certificate has expired, or is not valid yet. Entra, for example, answers AADSTS700027
          which names the thumbprint but not the reason.
        - The private key is held by a provider that will not perform RSA-SHA256, which is
          what a CNG key marked for key exchange only does.

        The store search covers CurrentUser then LocalMachine. That order matters: a
        certificate present in both is almost always the same certificate, and the user
        store copy is the one whose private key the current process can reach without
        elevation.

    .PARAMETER Thumbprint
        SHA-1 thumbprint, with or without spaces, case-insensitive

    .PARAMETER Path
        Path to a PFX file

    .PARAMETER Password
        Password protecting the PFX file

    .PARAMETER Certificate
        An already-loaded certificate object, returned as-is after validation

    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2

    .EXAMPLE
        PS> Get-TestCertificate -Thumbprint '9FC871A73BCE94325FD5E05DA33CBFF651E0A467'

        DESCRIPTION: Finds the certificate in the current user's personal store
        OUTPUT: The X509Certificate2, with its private key
        USE CASE: The normal path, called by Connect-TestEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(DefaultParameterSetName = 'Thumbprint')]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Thumbprint')]
        [string]$Thumbprint,

        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Path')]
        [securestring]$Password,

        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $resolved = $null

    switch ($PSCmdlet.ParameterSetName) {
        'Object' {
            $resolved = $Certificate
        }

        'Path' {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "Certificate file not found: $Path" -ErrorAction Stop
                return
            }
            $full = (Resolve-Path -LiteralPath $Path).ProviderPath
            try {
                # X509KeyStorageFlags.Exportable is deliberately NOT set. The key only has to
                # sign, and a key loaded exportable can be written back out of the process by
                # anything that later gets hold of the object.
                $resolved = if ($Password) {
                    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full, $Password)
                }
                else {
                    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full)
                }
            }
            catch {
                throw (New-Object System.Exception("Could not load the certificate at ${full}: $($_.Exception.Message)", $_.Exception))
            }
        }

        'Thumbprint' {
            # Portals print thumbprints with spaces and the certificate store
            # displays them uppercase; accept whatever was pasted.
            $wanted = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
            if ($wanted.Length -ne 40) {
                Write-Error "A SHA-1 thumbprint is 40 hex characters; got $($wanted.Length) after stripping separators." -ErrorAction Stop
                return
            }

            foreach ($storePath in 'Cert:\CurrentUser\My', 'Cert:\LocalMachine\My') {
                $found = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
                    Where-Object { $_.Thumbprint -eq $wanted } |
                    Select-Object -First 1
                if ($found) {
                    Write-Verbose "Found certificate $wanted in $storePath"
                    $resolved = $found
                    break
                }
            }

            if (-not $resolved) {
                Write-Error ("No certificate with thumbprint $wanted in Cert:\CurrentUser\My or " +
                    "Cert:\LocalMachine\My. Import the PFX, or pass -CertificatePath instead.") -ErrorAction Stop
                return
            }
        }
    }

    if (-not $resolved.HasPrivateKey) {
        Write-Error ("Certificate $($resolved.Thumbprint) has no private key. Only the public half is " +
            "installed, which is enough to verify a signature and not enough to make one. Import the " +
            "PFX rather than the CER.") -ErrorAction Stop
        return
    }

    $now = [DateTime]::Now
    if ($now -gt $resolved.NotAfter) {
        Write-Error ("Certificate $($resolved.Thumbprint) expired on $($resolved.NotAfter). The directory will " +
            "reject an assertion signed with it (AADSTS700027).") -ErrorAction Stop
        return
    }
    if ($now -lt $resolved.NotBefore) {
        Write-Error ("Certificate $($resolved.Thumbprint) is not valid until $($resolved.NotBefore).") -ErrorAction Stop
        return
    }

    # Ask for the RSA key now rather than at signing time. A CNG key created for key exchange
    # only returns here and then fails inside SignData, by which point the error names a
    # cryptographic operation rather than the certificate that cannot do it.
    $rsa = $null
    try {
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($resolved)
    }
    catch {
        Write-Verbose "GetRSAPrivateKey threw: $($_.Exception.Message)"
    }
    if (-not $rsa) {
        Write-Error ("Certificate $($resolved.Thumbprint) has a private key that is not RSA, or is held by " +
            "a provider this process cannot use for signing. Client assertions must be RS256.") -ErrorAction Stop
        return
    }

    return $resolved
}
