function Protect-AuthentikSecret {
    <#
    .SYNOPSIS
        Encrypts a token for storage on disk where the platform can, and says so where it cannot

    .DESCRIPTION
        The service account token is the durable credential and has to be written somewhere.
        On Windows it is protected with DPAPI through ConvertFrom-SecureString, which ties it
        to the user and machine that wrote it. Anywhere else ConvertFrom-SecureString returns a
        hex encoding of the plaintext rather than anything encrypted, so this refuses to call
        the result protected: it warns, returns the value with Method None, and points at
        -UseSecretStore, which is the portable path.

        The result is checked rather than trusted. The protected value must differ from the
        input, and where it is hex it must not decode to something containing the plaintext,
        because that is exactly what an unencrypted platform produces.

    .PARAMETER PlainText
        The token to protect.

    .OUTPUTS
        PSCustomObject with Method (DPAPI or None) and Value.

    .EXAMPLE
        PS> $protected = Protect-AuthentikSecret -PlainText $token

        DESCRIPTION: Protects a token for the credential record
        OUTPUT: Method 'DPAPI' and an opaque value on Windows
        USE CASE: Export-AuthentikCredential's default storage

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The plaintext is the value being protected; the SecureString is the route to DPAPI.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PlainText
    )

    try {
        $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
            ($PSVersionTable.PSObject.Properties['Platform'] -and $PSVersionTable.Platform -eq 'Win32NT') -or
            ($env:OS -eq 'Windows_NT')
        if (-not $onWindows) {
            throw 'DPAPI is only available on Windows.'
        }

        $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
        $protected = ConvertFrom-SecureString -SecureString $secure -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($protected) -or $protected -eq $PlainText) {
            throw 'ConvertFrom-SecureString did not return a protected value.'
        }

        if ($protected -match '^[0-9a-fA-F]+$' -and ($protected.Length % 2) -eq 0) {
            try {
                $raw = [byte[]]::new($protected.Length / 2)
                for ($i = 0; $i -lt $raw.Length; $i++) {
                    $raw[$i] = [Convert]::ToByte($protected.Substring($i * 2, 2), 16)
                }
                if ([System.Text.Encoding]::Unicode.GetString($raw).Contains($PlainText)) {
                    throw 'the protected value still contains the plaintext.'
                }
            }
            catch [System.FormatException] {
                Write-Verbose 'Protected value is not a hex encoding, which is the desired outcome.'
            }
        }

        return [PSCustomObject]@{ Method = 'DPAPI'; Value = $protected }
    }
    catch {
        Write-Warning ("This platform cannot encrypt the credential at rest with DPAPI " +
            "($($_.Exception.Message)). The token will be written UNPROTECTED, guarded only by " +
            'file permissions. Pass -UseSecretStore for encrypted storage here.')
        return [PSCustomObject]@{ Method = 'None'; Value = $PlainText }
    }
}
