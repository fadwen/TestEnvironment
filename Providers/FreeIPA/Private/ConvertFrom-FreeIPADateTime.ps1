function ConvertFrom-FreeIPADateTime {
    <#
    .SYNOPSIS
        Reads a FreeIPA date value into a DateTimeOffset

    .DESCRIPTION
        FreeIPA's JSON carries a date as an object, {"__datetime__": "20261210024734Z"}, and
        the generalized-time string inside it is always UTC. A value may also arrive as that
        bare string, as a list of one such object - most attributes are multi-valued in LDAP -
        or as nothing at all. Every shape is handled here, once, and anything unreadable is
        $null rather than an exception, because a report row with a blank expiry is more
        useful than a report that stopped.

    .PARAMETER Value
        The value as it came out of ConvertFrom-Json.

    .OUTPUTS
        System.DateTimeOffset, or $null.

    .EXAMPLE
        PS> ConvertFrom-FreeIPADateTime -Value $user.krbpasswordexpiration

        DESCRIPTION: Reads a user's password expiry
        OUTPUT: The expiry as a DateTimeOffset in UTC
        USE CASE: The report

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([DateTimeOffset])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return $null }
        $Value = $Value[0]
    }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [DateTime]) { return [DateTimeOffset]::new($Value.ToUniversalTime(), [TimeSpan]::Zero) }

    $text = $null
    if ($Value -is [string]) { $text = $Value }
    elseif ($Value.PSObject.Properties['__datetime__']) { $text = [string]$Value.__datetime__ }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($text, 'yyyyMMddHHmmssZ', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) {
        return [DateTimeOffset]::new($parsed, [TimeSpan]::Zero)
    }
    try {
        return [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    }
    catch {
        return $null
    }
}
