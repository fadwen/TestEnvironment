function ConvertFrom-TestBase64Url {
    <#
    .SYNOPSIS
        Decodes a base64url string back to bytes

    .DESCRIPTION
        The inverse of ConvertTo-TestBase64Url. Restores the padding [Convert] requires
        before undoing the URL-safe substitutions.

        This exists so the tests can prove the encoder round-trips byte for byte. Leading
        zero bytes are the case that catches a naive implementation, because they survive
        base64 but disappear from anything that goes via a numeric type on the way back.

    .PARAMETER Text
        The base64url text to decode

    .OUTPUTS
        System.Byte[]

    .EXAMPLE
        PS> ConvertFrom-TestBase64Url -Text 'eyJhbGciOiJSUzI1NiJ9'

        DESCRIPTION: Decodes a JWT header segment
        OUTPUT: The UTF-8 bytes of {"alg":"RS256"}
        USE CASE: Verifying in tests that an assertion segment says what it should

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $padded = $Text.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
        1 { Write-Error "Not valid base64url: length $($Text.Length) leaves one character over." -ErrorAction Stop; return }
    }

    return [Convert]::FromBase64String($padded)
}
