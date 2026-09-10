function Unprotect-AuthentikSecret {
    <#
    .SYNOPSIS
        Recovers a token that Protect-AuthentikSecret wrote

    .DESCRIPTION
        The inverse of Protect-AuthentikSecret, switched on the method the record says was
        used. A DPAPI value is bound to the user and machine that created it, so the failure
        that matters is a record copied from elsewhere; the error says that, and says to
        re-run the bootstrap on this machine, rather than reporting a cryptographic detail.

    .PARAMETER Method
        How the value was protected: DPAPI or None.

    .PARAMETER Value
        The stored value.

    .OUTPUTS
        System.String. The token.

    .EXAMPLE
        PS> Unprotect-AuthentikSecret -Method DPAPI -Value $record.tokenProtected

        DESCRIPTION: Recovers the token from a credential record
        OUTPUT: The plaintext token
        USE CASE: Import-AuthentikCredential

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DPAPI', 'None')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    if ($Method -eq 'None') { return $Value }

    try {
        $secure = ConvertTo-SecureString -String $Value -ErrorAction Stop
        return ConvertFrom-TestSecureString -SecureString $secure
    }
    catch {
        throw ('The stored token could not be decrypted. DPAPI ties it to the user account and ' +
            'machine that created it, so this usually means the record was copied from elsewhere. ' +
            'Re-run New-TestServiceApp -Force with an API token to mint a new one on this machine. ' +
            "Underlying error: $($_.Exception.Message)")
    }
}
