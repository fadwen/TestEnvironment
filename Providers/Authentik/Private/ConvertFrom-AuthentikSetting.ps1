function ConvertFrom-AuthentikSetting {
    <#
    .SYNOPSIS
        Turns a key=value;key=value CSV cell into a typed hashtable

    .DESCRIPTION
        Several seed files carry an object's settings in one cell rather than a column per
        setting, because the settings differ by type: a password policy has a minimum length
        and a GeoIP policy has a country list, and a CSV with a column for each would be
        mostly empty. The cell is key=value pairs separated by semicolons. A value of TRUE or
        FALSE becomes a boolean, a whole number becomes an integer, a value containing | becomes
        an array of those parts, each typed the same way, and anything else stays a string. A
        comma is not a separator, so an error message can contain one.

    .PARAMETER Text
        The cell. Empty or whitespace yields an empty hashtable.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary

    .EXAMPLE
        PS> ConvertFrom-AuthentikSetting -Text 'length_min=12;check_zxcvbn=TRUE;countries=US|GB'

        DESCRIPTION: Parses three settings
        OUTPUT: An ordered hashtable with an int, a bool and a two-element string array
        USE CASE: Building the body of a typed policy from its CSV row

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    $typed = {
        param([string]$value)
        $trimmed = $value.Trim()
        if ($trimmed -eq 'TRUE') { return $true }
        if ($trimmed -eq 'FALSE') { return $false }
        if ($trimmed -match '^-?\d+$') { return [int]$trimmed }
        return $trimmed
    }

    $result = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    foreach ($pair in @($Text -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $index = $pair.IndexOf('=')
        if ($index -lt 1) { throw "Setting '$pair' is not in key=value form." }
        $key = $pair.Substring(0, $index).Trim()
        $value = $pair.Substring($index + 1)

        if ($value.Contains('|')) {
            $result[$key] = @($value -split '\|' | ForEach-Object { & $typed $_ })
        }
        else {
            $result[$key] = & $typed $value
        }
    }

    return $result
}
