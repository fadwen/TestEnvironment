function Get-AuthentikEnvironmentReport {
    <#
    .SYNOPSIS
        Reads back what the seed created and renders it to the console or a file

    .DESCRIPTION
        Lists the seeded users with their memberships and lab attributes, the groups with
        their parents and member counts, the applications with their provider type and
        launch URL, the policies with what they are bound to, and the notification rules
        with their transports. Only objects the module can prove it owns are included, so the
        report is a picture of the seed and not of the instance.

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
        PSCustomObject. The report, when -PassThru is supplied or the format is Console with
        -PassThru.

    .EXAMPLE
        PS> Get-AuthentikEnvironmentReport

        DESCRIPTION: Prints the seeded estate to the console
        OUTPUT: One table per object type
        USE CASE: A quick look after seeding

    .EXAMPLE
        PS> Get-AuthentikEnvironmentReport -OutputFormat JSON -OutputPath ./authentik-report.json

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

    $connection = Get-AuthentikConnection

    if ($OutputFormat -ne 'Console' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $groups = @(Get-AuthentikSeededObject -Type Groups -Connection $connection)
    $groupNameByPk = @{}
    foreach ($group in $groups) { $groupNameByPk[[string]$group.pk] = $group.name }

    $users = @(Get-AuthentikSeededObject -Type Users -IncludeServiceAccount -Connection $connection)
    $memberCountByGroup = @{}
    foreach ($user in $users) {
        foreach ($pk in @($user.groups)) {
            $key = [string]$pk
            if (-not $memberCountByGroup.ContainsKey($key)) { $memberCountByGroup[$key] = 0 }
            $memberCountByGroup[$key]++
        }
    }

    $applications = @(Get-AuthentikSeededObject -Type Applications -Connection $connection)
    $policies = @(Get-AuthentikSeededObject -Type Policies -Connection $connection)
    $rules = @(Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)
    $transports = @(Get-AuthentikSeededObject -Type NotificationTransports -Connection $connection)
    $transportNameByPk = @{}
    foreach ($transport in $transports) { $transportNameByPk[[string]$transport.pk] = $transport.name }

    # Bindings tell which application each policy governs. Read per seeded application, which
    # is the side that has a filter.
    $boundTo = @{}
    foreach ($application in $applications) {
        try {
            $bindings = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                    -Query @{ target = [string]$application.pbm_uuid } -Connection $connection -Paginate)
            foreach ($binding in $bindings) {
                if (-not $binding.policy) { continue }
                $key = [string]$binding.policy
                if (-not $boundTo.ContainsKey($key)) { $boundTo[$key] = @() }
                $boundTo[$key] += [PSCustomObject]@{ Slug = $application.slug; Order = $binding.order; Enabled = $binding.enabled }
            }
        }
        catch {
            Write-Verbose "Could not read bindings for $($application.slug): $($_.Exception.Message)"
        }
    }

    $attribute = { param($object, $name) if ($object.attributes -and $object.attributes.PSObject.Properties[$name]) { $object.attributes.$name } else { $null } }

    $report = [PSCustomObject]@{
        GeneratedUtc      = [DateTime]::UtcNow.ToString('o')
        BaseUrl           = $connection.BaseUrl
        Prefix            = $connection.Prefix
        AuthType          = $connection.AuthType
        Users             = @($users | Sort-Object username | ForEach-Object {
                [PSCustomObject]@{
                    Username   = $_.username
                    Name       = $_.name
                    Type       = $_.type
                    Active     = [bool]$_.is_active
                    Groups     = (@($_.groups | ForEach-Object { if ($groupNameByPk.ContainsKey([string]$_)) { $groupNameByPk[[string]$_] } }) -join '; ')
                    Department = (& $attribute $_ 'labDepartment')
                    Clearance  = (& $attribute $_ 'labClearanceLevel')
                    Contractor = [bool](& $attribute $_ 'labIsContractor')
                    RiskScore  = (& $attribute $_ 'labRiskScore')
                }
            })
        Groups            = @($groups | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name        = $_.name
                    Parents     = (@($_.parents | ForEach-Object { if ($groupNameByPk.ContainsKey([string]$_)) { $groupNameByPk[[string]$_] } }) -join '; ')
                    MemberCount = $(if ($memberCountByGroup.ContainsKey([string]$_.pk)) { $memberCountByGroup[[string]$_.pk] } else { 0 })
                    Category    = (& $attribute $_ 'labCategory')
                }
            })
        Applications      = @($applications | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name         = $_.name
                    Slug         = $_.slug
                    ProviderType = $(if ($_.provider_obj) { $_.provider_obj.verbose_name } else { 'None' })
                    LaunchUrl    = $_.meta_launch_url
                    Hidden       = [bool]$_.meta_hide
                }
            })
        Policies          = @($policies | Sort-Object name | ForEach-Object {
                $bindings = @($boundTo[[string]$_.pk])
                [PSCustomObject]@{
                    Name    = $_.name
                    Type    = $_.verbose_name
                    BoundTo = (@($bindings | ForEach-Object { $_.Slug }) -join '; ')
                    Enabled = (@($bindings | ForEach-Object { $_.Enabled }) -join '; ')
                }
            })
        NotificationRules = @($rules | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name       = $_.name
                    Severity   = $_.severity
                    Transports = (@($_.transports | ForEach-Object { if ($transportNameByPk.ContainsKey([string]$_)) { $transportNameByPk[[string]$_] } else { $_ } }) -join '; ')
                }
            })
    }

    switch ($OutputFormat) {
        'Console' {
            Write-TestMessage -Message "Authentik Test Environment Report ($($connection.BaseUrl))" -Type Header
            foreach ($section in 'Users', 'Groups', 'Applications', 'Policies', 'NotificationRules') {
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
            foreach ($section in 'Users', 'Groups', 'Applications', 'Policies', 'NotificationRules') {
                $file = Join-Path -Path $OutputPath -ChildPath "AuthentikLab$section.csv"
                $report.$section | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
            }
            Write-Verbose "Wrote five CSV files to $OutputPath"
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
            $fragments = foreach ($section in 'Users', 'Groups', 'Applications', 'Policies', 'NotificationRules') {
                "<h2>$section ($(@($report.$section).Count))</h2>"
                if (@($report.$section).Count -gt 0) { $report.$section | ConvertTo-Html -Fragment }
            }
            $html = @(
                '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Authentik Test Environment Report</title>', $style, '</head><body>'
                "<h1>Authentik Test Environment Report</h1><p>$($connection.BaseUrl) &middot; prefix $($connection.Prefix) &middot; generated $($report.GeneratedUtc)</p>"
                $fragments
                '</body></html>'
            ) -join "`n"
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($html))
            Write-Verbose "Wrote $OutputPath"
        }
    }

    if ($PassThru) { return $report }
}
