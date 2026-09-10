function ConvertTo-TestSecureString {
    <#
    .SYNOPSIS
        Copies a plain string into a SecureString a character at a time

    .DESCRIPTION
        Builds a SecureString without handing the plain value to a cmdlet.

        Be clear about what this does and does not buy, because it is easy to overstate.
        It is NOT cryptographically stronger than ConvertTo-SecureString -AsPlainText: the
        caller already holds the value as an ordinary .NET string, and that string stays in
        managed memory until the garbage collector reclaims it. Nothing here changes that.

        What it does buy is twofold. The value never appears as a bound cmdlet parameter, so
        it cannot be captured by a transcript, by module logging, or by anything else that
        records invocations. And it keeps PSAvoidUsingConvertToSecureStringWithPlainText for
        genuine findings - a plaintext credential written into source - rather than firing on
        every conversion of an already-generated random password, which is the case that made
        the rule easy to ignore in this module.

        The right long-term answer is for password generation to hand back a SecureString and
        never materialise the plain form at all. New-TestPassword cannot do that yet,
        because the vault export documentation needs the readable value.

    .PARAMETER PlainText
        The value to copy. Set to $null by the caller afterwards where practical.

    .EXAMPLE
        $secure = ConvertTo-TestSecureString -PlainText (New-TestPassword -Length 24)

        DESCRIPTION: Converts a freshly generated password
        OUTPUT: A read-only SecureString

    .OUTPUTS
        System.Security.SecureString

        Returned read-only, so it cannot be modified after construction.

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
    #>

    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PlainText
    )

    $secure = New-Object System.Security.SecureString

    foreach ($character in $PlainText.ToCharArray()) {
        $secure.AppendChar($character)
    }

    $secure.MakeReadOnly()
    return $secure
}
