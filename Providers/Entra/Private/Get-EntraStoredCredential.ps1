function Get-EntraStoredCredential {
    <#
    .SYNOPSIS
        Loads the bootstrapped credential from wherever the record says it lives

    .DESCRIPTION
        Turns the credential record written by New-EntraServiceApp back into a client id and
        a usable certificate, so a caller only has to name the tenant.

        The record is the authority on where the private key is, not this function. That matters
        because the two locations behave differently and guessing wrong produces the least
        helpful possible error: a certificate store lookup that finds nothing on a machine where
        the key is sitting in a vault, reported as "no certificate with that thumbprint".

        For the vault path the PFX is reconstituted in memory and never written to disk. It is
        loaded with EphemeralKeySet where the platform supports it, so importing the credential
        does not quietly install it into the machine's certificate store as a side effect of
        being read.

    .PARAMETER TenantId
        Tenant whose record to read

    .PARAMETER VaultPassword
        Password for the vault, when the key is stored in one

    .OUTPUTS
        System.Collections.Hashtable with ClientId and Certificate.

    .EXAMPLE
        PS> Get-EntraStoredCredential -TenantId $tenant

        DESCRIPTION: Reads the record and returns the credential it names
        OUTPUT: A hashtable carrying the client id and an X509Certificate2
        USE CASE: Called by Connect-EntraEnvironment -UseSecretStore

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    $recordPath = Get-TestCredentialPath -TenantId $TenantId
    if (-not (Test-Path -LiteralPath $recordPath)) {
        Write-Error ("No credential record for tenant $TenantId at $recordPath. Run " +
            "Connect-TestEnvironment -Provider Entra -Interactive followed by New-TestServiceApp first.") -ErrorAction Stop
        return
    }

    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # Records written before the vault path existed have no keyProtection, and the key is in
    # the certificate store. Defaulting keeps them readable rather than failing on a field
    # that did not exist when they were written.
    $protection = if ($record.PSObject.Properties['keyProtection'] -and $record.keyProtection) {
        $record.keyProtection
    }
    else { 'CertificateStore' }

    $certificate = switch ($protection) {
        'SecretStore' {
            $encoded = Get-TestVaultSecret -VaultName $record.vaultName -SecretName $record.secretName -VaultPassword $VaultPassword
            $password = Get-TestVaultSecret -VaultName $record.vaultName -SecretName "$($record.secretName)-password" -VaultPassword $VaultPassword

            $pfx = [Convert]::FromBase64String($encoded)
            try {
                # Ephemeral where available: reading the credential should not have the side
                # effect of installing it. PowerShell 5.1 has no such flag, so it falls back to
                # a non-persisted user key set there.
                $flags = if ($PSVersionTable.PSEdition -eq 'Desktop') {
                    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet
                }
                else {
                    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
                }
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx, $password, $flags)
            }
            finally {
                [Array]::Clear($pfx, 0, $pfx.Length)
            }
        }
        default {
            Get-TestCertificate -Thumbprint $record.certificateThumbprint
        }
    }

    if (-not $certificate) {
        Write-Error "The credential record names a certificate that could not be loaded." -ErrorAction Stop
        return
    }

    return @{
        ClientId      = $record.clientId
        Certificate   = $certificate
        KeyProtection = $protection
        DisplayName   = $record.displayName
    }
}
