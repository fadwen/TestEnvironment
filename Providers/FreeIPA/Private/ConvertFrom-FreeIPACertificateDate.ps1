function ConvertFrom-FreeIPACertificateDate {
    <#
    .SYNOPSIS
        Parses the date format the certificate commands use, which is not the one everything else uses

    .DESCRIPTION
        Every other FreeIPA command returns a date as a {"__datetime__": "yyyyMMddHHmmssZ"}
        object, which ConvertFrom-FreeIPADateTime reads. The certificate commands return the
        validity dates as text in the C library's asctime form, "Mon Sep 11 22:16:42 2028
        UTC", with the day padded by a space when it has one digit. This reads that form and
        returns a UTC DateTime, or $null for anything else, so a report never fails on a
        date it did not expect.

    .PARAMETER Value
        The text as returned.

    .OUTPUTS
        System.DateTime in UTC, or $null.

    .EXAMPLE
        PS> ConvertFrom-FreeIPACertificateDate -Value 'Mon Sep 11 22:16:42 2028 UTC'

        DESCRIPTION: Parses a validity date
        OUTPUT: The DateTime 2028-09-11 22:16:42 with Kind Utc
        USE CASE: Deciding whether a seeded certificate has expired

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Nullable[datetime]])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [array]) { if ($Value.Count -eq 0) { return $null } else { $Value = $Value[0] } }

    $text = ([string]$Value) -replace '\s+', ' '
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($text, 'ddd MMM d HH:mm:ss yyyy \U\T\C', $culture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) {
        return [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)
    }
    return $null
}
