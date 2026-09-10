function Set-TestVaultSecret {
    <#
    .SYNOPSIS
        Stores the service app's private key in a SecretStore vault

    .DESCRIPTION
        The secret this holds is the certificate's PFX, base64 encoded - the private key that
        signs every client assertion. It is the one genuinely sensitive thing the module
        produces, and it is why the vault path exists at all.

        Stored as a SecureString rather than a plain secret. On Windows that means SecretStore
        encrypts it with the vault key rather than holding it as recoverable text, and it keeps
        the value out of any accidental Get-Secret output that renders objects.

    .PARAMETER VaultName
        Vault to store it in

    .PARAMETER SecretName
        Name of the secret, which is derived from the tenant so several tenants can coexist

    .PARAMETER PlainText
        The base64-encoded PFX to store

    .OUTPUTS
        System.Boolean, true when the secret was written.

    .EXAMPLE
        PS> Set-TestVaultSecret -VaultName TestEnvironment -SecretName $name -PlainText $pfx

        DESCRIPTION: Stores the private key
        OUTPUT: True
        USE CASE: Called by New-TestServiceApp -UseSecretStore

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The PFX is already in memory as a base64 string - it has to be, to have been exported. Converting it to a SecureString is what puts it into the vault encrypted rather than as recoverable text.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PlainText
    )

    if (-not $PSCmdlet.ShouldProcess("$VaultName\$SecretName", "Store the service app's private key")) {
        return $false
    }

    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    Set-Secret -Name $SecretName -SecureStringSecret $secure -Vault $VaultName -ErrorAction Stop

    Write-Verbose "Stored '$SecretName' in vault '$VaultName'"
    return $true
}
