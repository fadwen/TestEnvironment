function ConvertFrom-FreeIPADnsName {
    <#
    .SYNOPSIS
        Reads the text out of the {"__dns_name__": "..."} object the DNS commands return

    .DESCRIPTION
        A zone name, a record name and an SOA contact all arrive from FreeIPA as an object
        with one property, __dns_name__, usually inside a one-element array, and a plain
        cast of that object to a string gives '@{__dns_name__=...}' rather than the name.
        This returns the name, or the value itself when it is already text, or an empty
        string for nothing, so a comparison against a name the seed derived is a comparison
        of two strings.

    .PARAMETER Value
        The value as returned: an array, the object, or text.

    .OUTPUTS
        System.String.

    .EXAMPLE
        PS> ConvertFrom-FreeIPADnsName -Value @([PSCustomObject]@{ __dns_name__ = 'zz-test-lab.ipa.example.com.' })

        DESCRIPTION: Reads a zone name
        OUTPUT: 'zz-test-lab.ipa.example.com.'
        USE CASE: Proving a zone is the seed's by its name and contact

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return '' }
        $Value = $Value[0]
    }
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value.PSObject.Properties['__dns_name__']) { return [string]$Value.__dns_name__ }
    return [string]$Value
}
