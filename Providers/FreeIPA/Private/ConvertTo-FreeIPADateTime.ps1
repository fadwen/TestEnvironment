function ConvertTo-FreeIPADateTime {
    <#
    .SYNOPSIS
        Formats a point in time as the generalized-time string FreeIPA accepts

    .DESCRIPTION
        A FreeIPA DATETIME parameter - a principal expiration, a token's not-after, a password
        expiry set by an administrator - is sent as generalized time in UTC,
        'yyyyMMddHHmmssZ'. The seed expresses those as offsets from now in the CSVs ('-14'
        days, '-1' day), and this turns the resulting time into the one string shape the
        server parses without complaint.

    .PARAMETER Value
        The point in time. Converted to UTC before formatting.

    .OUTPUTS
        System.String.

    .EXAMPLE
        PS> ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::UtcNow.AddDays(-14))

        DESCRIPTION: Formats a date two weeks ago
        OUTPUT: 20260827120000Z
        USE CASE: An expired principal in the users step

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$Value
    )

    return $Value.ToUniversalTime().ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture) + 'Z'
}
