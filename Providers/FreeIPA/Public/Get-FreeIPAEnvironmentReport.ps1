function Get-FreeIPAEnvironmentReport {
    <#
    .SYNOPSIS
        Reads back what the seed created and renders it to the console or a file

    .DESCRIPTION
        Lists the seeded users in every lifecycle state with their memberships, class,
        authentication type and expiries, the groups with their type, GID, member counts and
        parents, the host groups with their member counts and parents, and the hosts with
        their operating system, class, host groups, manager and whether anything has ever
        enrolled. Only objects the module can prove it owns are included, so the report is a
        picture of the seed and not of the realm.

        Console output is for a person; JSON, CSV and HTML are for a file, and each writes
        UTF-8 explicitly, because the seeded names carry accents on purpose and the default
        encoding on Windows PowerShell would destroy them.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console.

    .PARAMETER PassThru
        Returns the report object as well.

    .OUTPUTS
        PSCustomObject. The report, when -PassThru is supplied.

    .EXAMPLE
        PS> Get-FreeIPAEnvironmentReport

        DESCRIPTION: Prints the seeded estate to the console
        OUTPUT: One table per object type
        USE CASE: A quick look after seeding

    .EXAMPLE
        PS> Get-FreeIPAEnvironmentReport -OutputFormat JSON -OutputPath ./freeipa-report.json

        DESCRIPTION: Writes the report as JSON
        OUTPUT: The file, and nothing on the pipeline
        USE CASE: Diffing the estate before and after a change

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The console format exists to be read by a person at the console.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    if ($OutputFormat -ne 'Console' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { if ($null -eq $value) { '' } else { [string]$value } } }
    $list = { param($value) if ($null -eq $value) { @() } else { @($value | ForEach-Object { [string]$_ }) } }
    $has = { param($entry, $name) $entry.PSObject.Properties[$name] -and $null -ne $entry.$name }
    $get = { param($entry, $name) if (& $has $entry $name) { $entry.$name } else { $null } }
    $prefixed = { param($names) @($names | Where-Object { ([string]$_).StartsWith($marker.NamePrefix, [StringComparison]::OrdinalIgnoreCase) }) }
    $withoutMarker = { param($text) ([string]$text).Replace($marker.Marker, '').Trim() }
    $classOf = { param($entry) (@(& $list (& $get $entry 'userclass') | Where-Object { $_ -ne $marker.Tag }) -join '; ') }
    $whenUtc = { param($value) $offset = ConvertFrom-FreeIPADateTime -Value $value; if ($offset) { $offset.UtcDateTime } else { $null } }

    $active = @(Get-FreeIPASeededObject -Type Users -IncludeServiceAccount -Detail -Connection $connection)
    $preserved = @(Get-FreeIPASeededObject -Type PreservedUsers -Detail -Connection $connection)
    $staged = @(Get-FreeIPASeededObject -Type StagedUsers -Detail -Connection $connection)
    $groups = @(Get-FreeIPASeededObject -Type Groups -Detail -Connection $connection)
    $hostgroups = @(Get-FreeIPASeededObject -Type Hostgroups -Detail -Connection $connection)
    $hosts = @(Get-FreeIPASeededObject -Type Hosts -Detail -Connection $connection)

    $userRow = {
        param($entry, $lifecycle)
        [PSCustomObject]@{
            Login             = (& $first $entry.uid)
            Name              = (& $first (& $get $entry 'cn'))
            Lifecycle         = $lifecycle
            Class             = (& $classOf $entry)
            Title             = (& $first (& $get $entry 'title'))
            OrgUnit           = (& $first (& $get $entry 'ou'))
            Manager           = (& $first (& $get $entry 'manager'))
            Groups            = ((& $prefixed (& $list (& $get $entry 'memberof_group'))) -join '; ')
            AuthType          = ((& $list (& $get $entry 'ipauserauthtype')) -join '; ')
            PasswordExpires   = (& $whenUtc (& $get $entry 'krbpasswordexpiration'))
            PrincipalExpires  = (& $whenUtc (& $get $entry 'krbprincipalexpiration'))
            PublicKeys        = @(& $list (& $get $entry 'ipasshpubkey')).Count
        }
    }

    $groupType = {
        param($entry)
        $classes = @(& $list (& $get $entry 'objectclass'))
        if ($classes -contains 'ipaexternalgroup') { 'external' }
        elseif ($classes -contains 'posixgroup') { 'posix' }
        else { 'nonposix' }
    }

    $report = [PSCustomObject]@{
        GeneratedUtc = [DateTime]::UtcNow.ToString('o')
        BaseUrl      = $connection.BaseUrl
        Prefix       = $connection.Prefix
        AuthType     = $connection.AuthType
        Users        = @(
            @($active | ForEach-Object { & $userRow $_ $(if ((& $get $_ 'nsaccountlock') -eq $true) { 'Disabled' } else { 'Active' }) }) +
            @($preserved | ForEach-Object { & $userRow $_ 'Preserved' }) +
            @($staged | ForEach-Object { & $userRow $_ 'Staged' }) | Sort-Object Login
        )
        Groups       = @($groups | ForEach-Object {
                [PSCustomObject]@{
                    Name         = (& $first $_.cn)
                    Type         = (& $groupType $_)
                    Gid          = (& $first (& $get $_ 'gidnumber'))
                    Description  = (& $withoutMarker (& $first (& $get $_ 'description')))
                    MemberUsers  = @(& $list (& $get $_ 'member_user')).Count
                    MemberGroups = ((& $list (& $get $_ 'member_group')) -join '; ')
                    MemberOf     = ((& $prefixed (& $list (& $get $_ 'memberof_group'))) -join '; ')
                }
            } | Sort-Object Name)
        Hostgroups   = @($hostgroups | ForEach-Object {
                [PSCustomObject]@{
                    Name         = (& $first $_.cn)
                    Description  = (& $withoutMarker (& $first (& $get $_ 'description')))
                    MemberHosts  = @(& $list (& $get $_ 'member_host')).Count
                    MemberGroups = ((& $list (& $get $_ 'member_hostgroup')) -join '; ')
                    MemberOf     = ((& $prefixed (& $list (& $get $_ 'memberof_hostgroup'))) -join '; ')
                }
            } | Sort-Object Name)
        Hosts        = @($hosts | ForEach-Object {
                $fqdn = (& $first $_.fqdn)
                [PSCustomObject]@{
                    Name            = $fqdn
                    Description     = (& $withoutMarker (& $first (& $get $_ 'description')))
                    OperatingSystem = (& $first (& $get $_ 'nsosversion'))
                    Platform        = (& $first (& $get $_ 'nshardwareplatform'))
                    Locality        = (& $first (& $get $_ 'l'))
                    Class           = (& $classOf $_)
                    Hostgroups      = ((& $prefixed (& $list (& $get $_ 'memberof_hostgroup'))) -join '; ')
                    ManagedBy       = (@(& $list (& $get $_ 'managedby_host') | Where-Object { $_ -ne $fqdn }) -join '; ')
                    Enrolled        = ((& $get $_ 'has_keytab') -eq $true)
                }
            } | Sort-Object Name)
    }

    switch ($OutputFormat) {
        'Console' {
            Write-TestMessage -Message "FreeIPA Test Environment Report ($($connection.BaseUrl))" -Type Header
            foreach ($section in $script:FreeIPAReportSections) {
                Write-Host "$section ($(@($report.$section).Count)):" -ForegroundColor Cyan
                if (@($report.$section).Count -gt 0) {
                    $report.$section | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
                }
                else { Write-Host '' }
            }
        }
        'JSON' {
            $json = $report | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($json))
            Write-Verbose "Wrote $OutputPath"
        }
        'CSV' {
            if (-not (Test-Path -LiteralPath $OutputPath)) { $null = New-Item -ItemType Directory -Path $OutputPath -Force }
            foreach ($section in $script:FreeIPAReportSections) {
                $file = Join-Path -Path $OutputPath -ChildPath "FreeIPALab$section.csv"
                $report.$section | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
            }
            Write-Verbose "Wrote $($script:FreeIPAReportSections.Count) CSV files to $OutputPath"
        }
        'HTML' {
            $style = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 2em; color: #222; }
h1 { font-size: 1.4em; } h2 { font-size: 1.1em; margin-top: 1.5em; }
table { border-collapse: collapse; } th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: left; }
th { background: #f0f0f0; }
</style>
'@
            $fragments = foreach ($section in $script:FreeIPAReportSections) {
                "<h2>$section ($(@($report.$section).Count))</h2>"
                if (@($report.$section).Count -gt 0) { $report.$section | ConvertTo-Html -Fragment }
            }
            $html = @(
                '<!DOCTYPE html><html><head><meta charset="utf-8"><title>FreeIPA Test Environment Report</title>', $style, '</head><body>'
                "<h1>FreeIPA Test Environment Report</h1><p>$($connection.BaseUrl) &middot; prefix $($connection.Prefix) &middot; generated $($report.GeneratedUtc)</p>"
                $fragments
                '</body></html>'
            ) -join "`n"
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($html))
            Write-Verbose "Wrote $OutputPath"
        }
    }

    if ($PassThru) { return $report }
}
