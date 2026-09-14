function Export-TestEnvironmentReport {
    <#
    .SYNOPSIS
        Writes a report built by New-TestEnvironmentReport as JSON, CSV or HTML
    .DESCRIPTION
        The one file writer behind every provider's report, so a JSON, CSV or HTML report looks
        the same whichever directory it describes, and the encoding rules are kept in one place.
        Every file is UTF-8: the seeded names carry accents and other writing systems on purpose,
        and the defaults - ASCII from Export-Csv on Windows PowerShell, the code page from
        Set-Content - would replace them with question marks and report success.

        JSON is the whole object. CSV is a folder with one file per section, named by the prefix
        and the section, an empty file for an empty section, so the folder always holds one file
        per section. HTML is one page with a heading and a table per section. In the CSV and HTML
        rows a multi-valued column is joined with a semicolon and a nested object is written as
        compact JSON, because the alternative is the literal text "System.Object[]", which looks
        like data and is not.
    .PARAMETER Report
        The report, as New-TestEnvironmentReport built it
    .PARAMETER OutputFormat
        JSON, CSV or HTML
    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Created if it does not exist.
    .PARAMETER FilePrefix
        What each CSV file name starts with, ahead of the section name
    .PARAMETER Title
        The HTML page title and heading. Defaults to "<Provider> Test Environment Report".
    .PARAMETER Note
        Lines written under the HTML heading, as text
    .PARAMETER Warning
        Lines written under the HTML heading and marked as warnings, for the one number a reader
        must not miss
    .OUTPUTS
        None. The path written is reported through Write-Verbose.
    .EXAMPLE
        PS> Export-TestEnvironmentReport -Report $report -OutputFormat CSV -OutputPath ./out -FilePrefix OktaLab

        Writes OktaLabUsers.csv, OktaLabGroups.csv and so on, one per section.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject]$Report,

        [Parameter(Mandatory = $true)]
        [ValidateSet('JSON', 'CSV', 'HTML')]
        [string]$OutputFormat,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$FilePrefix = '',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Note = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Warning = @()
    )

    if (-not $Title) { $Title = '{0} Test Environment Report' -f $Report.Provider }
    $sections = @($Report.Sections)

    # A row as a table can hold it: scalars as they are, lists joined, objects as compact JSON.
    $flatten = {
        param($row)
        $flat = [ordered]@{}
        foreach ($property in $row.PSObject.Properties) {
            $value = $property.Value
            if ($null -eq $value -or $value -is [string] -or $value -is [ValueType]) { $flat[$property.Name] = $value }
            elseif ($value -is [System.Collections.IDictionary] -or $value -is [PSCustomObject]) { $flat[$property.Name] = ($value | ConvertTo-Json -Compress -Depth 5) }
            elseif ($value -is [System.Collections.IEnumerable]) { $flat[$property.Name] = (@($value | ForEach-Object { [string]$_ }) -join '; ') }
            else { $flat[$property.Name] = [string]$value }
        }
        [PSCustomObject]$flat
    }
    $writeUtf8 = {
        param($path, $text)
        $directory = Split-Path -Path $path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
        [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::UTF8.GetBytes($text))
    }

    switch ($OutputFormat) {
        'JSON' {
            & $writeUtf8 $OutputPath ($Report | ConvertTo-Json -Depth 10)
        }
        'CSV' {
            if (-not (Test-Path -LiteralPath $OutputPath)) { $null = New-Item -ItemType Directory -Path $OutputPath -Force }
            foreach ($section in $sections) {
                $file = Join-Path -Path $OutputPath -ChildPath ('{0}{1}.csv' -f $FilePrefix, $section)
                $rows = @($Report.$section | ForEach-Object { & $flatten $_ })
                if ($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8 }
                else { & $writeUtf8 $file '' }
            }
        }
        'HTML' {
            $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
            $style = @'
<style>
body { font-family: Segoe UI, system-ui, sans-serif; margin: 2rem; color: #1f2933; }
h1 { border-bottom: 2px solid #005b9f; padding-bottom: .3rem; font-size: 1.4rem; }
h2 { margin-top: 2rem; color: #005b9f; font-size: 1.1rem; }
p.meta { color: #555; font-size: .9rem; }
p.warn { color: #b34700; font-weight: 600; }
table { border-collapse: collapse; width: 100%; margin-bottom: 1rem; }
th, td { border: 1px solid #d3d8de; padding: .4rem .6rem; text-align: left; font-size: .9rem; }
th { background: #eef3f8; }
tr:nth-child(even) td { background: #fafbfc; }
</style>
'@
            $meta = New-Object System.Collections.Generic.List[string]
            if ($Report.Target) { $meta.Add(('Target {0}' -f (& $encode $Report.Target))) }
            if ($Report.PSObject.Properties['Prefix'] -and $Report.Prefix) { $meta.Add(('Prefix {0}' -f (& $encode $Report.Prefix))) }
            $meta.Add(('Generated {0}' -f (& $encode $Report.GeneratedOn)))

            $body = New-Object System.Collections.Generic.List[string]
            $body.Add(('<h1>{0}</h1>' -f (& $encode $Title)))
            $body.Add(('<p class="meta">{0}</p>' -f ($meta -join ' &middot; ')))
            foreach ($line in $Note) { $body.Add(('<p>{0}</p>' -f (& $encode $line))) }
            foreach ($line in $Warning) { $body.Add(('<p class="warn">{0}</p>' -f (& $encode $line))) }
            foreach ($section in $sections) {
                $rows = @($Report.$section | ForEach-Object { & $flatten $_ })
                $body.Add(('<h2>{0} ({1})</h2>' -f (& $encode $section), $rows.Count))
                # ConvertTo-Html -Fragment encodes its input, so seeded names carrying accented
                # characters or an ampersand survive rather than corrupting the page.
                if ($rows.Count -gt 0) { $body.Add((($rows | ConvertTo-Html -Fragment) -join "`n")) }
            }
            $html = @(
                '<!DOCTYPE html>', '<html><head><meta charset="utf-8">', ('<title>{0}</title>' -f (& $encode $Title)), $style, '</head><body>'
                $body.ToArray()
                '</body></html>'
            ) -join "`n"
            & $writeUtf8 $OutputPath $html
        }
    }
    Write-Verbose "Wrote the $OutputFormat report to $OutputPath"
}
