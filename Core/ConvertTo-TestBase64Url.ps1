function ConvertTo-TestBase64Url {
    <#
    .SYNOPSIS
        Encodes bytes as base64url, the encoding JWT uses

    .DESCRIPTION
        Base64url is standard base64 with the two URL-unsafe characters substituted and the
        padding removed. RFC 7515 requires it for every part of a JWT, and an authorisation server rejects a
        client assertion encoded as plain base64 with an "invalid signature" error that says
        nothing about the encoding.

        The three transformations are not interchangeable with a naive -replace chain: the
        padding has to go before the substitutions, or a trailing '=' can survive into the
        output and the assertion is rejected.

    .PARAMETER Bytes
        The bytes to encode

    .OUTPUTS
        System.String. The base64url representation, unpadded.

    .EXAMPLE
        PS> ConvertTo-TestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes('{"alg":"RS256"}'))

        DESCRIPTION: Encodes a JWT header segment
        OUTPUT: eyJhbGciOiJSUzI1NiJ9
        USE CASE: Building each of the three dot-separated JWT segments

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
