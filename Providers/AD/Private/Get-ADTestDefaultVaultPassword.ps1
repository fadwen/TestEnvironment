function Get-ADTestDefaultVaultPassword {
    <#
    .SYNOPSIS
        Returns the module's documented default SecretStore vault password

    .DESCRIPTION
        The SecretStore this module creates needs a password, and the module has to be able
        to reach that vault again later without prompting - Remove-ADEnvironment resets
        the store during teardown and cannot ask a scheduled run for a password.

        So there is a default, and it is deliberately published: the help for both
        New-ADEnvironment and New-ADTestServiceAccount names it. This function exists to
        hold it in one place rather than as the same literal repeated at three call sites,
        which is how it was.

        Understand what this value is and is not. It is not a secret. It protects a vault of
        throwaway service account passwords in a test directory, and anyone who can read the
        module can read the password. That is an acceptable trade for a lab, and it is the
        reason PSAvoidUsingConvertToSecureStringWithPlainText firing here was noise rather
        than a finding. It would NOT be acceptable anywhere real - which is why callers can
        pass -VaultPassword and skip this entirely, and why -AllowPlaintextVault exists for
        anyone who would rather have no password than a known one.

    .EXAMPLE
        $vaultParams.Password = Get-ADTestDefaultVaultPassword

        DESCRIPTION: Uses the documented default when no password was supplied
        OUTPUT: A read-only SecureString

    .OUTPUTS
        System.Security.SecureString

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0

        Changing this value strands any vault created with the previous one. Remove the old
        vault with Remove-ADEnvironment before changing it.
    #>

    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param()

    return (ConvertTo-TestSecureString -PlainText 'ADTestEnvironmentPassword')
}
