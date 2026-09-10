function Get-AuthentikEnvironmentReport {
    <#
    .SYNOPSIS
        Reads back what the seed created and renders it to the console or a file

    .DESCRIPTION
        Lists the seeded users with their memberships and lab attributes, the groups with
        their parents, member counts and roles, the roles with their holders, the applications
        with their provider type, launch URL and who is admitted by binding, the scope mappings
        with the applications they shape, the entitlements with who holds them, the policies
        with their type and what they are bound to, the notification rules with their
        transports, and the tokens and invitations with their expiry. Only objects the module
        can prove it owns are included, so the report is a picture of the seed and not of the
        instance.

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

    $roles = @(Get-AuthentikSeededObject -Type Roles -Connection $connection)
    $roleNameByPk = @{}
    foreach ($role in $roles) { $roleNameByPk[[string]$role.pk] = $role.name }
    $groupsByRole = @{}
    foreach ($group in $groups) {
        foreach ($pk in @($group.roles)) {
            $key = [string]$pk
            if (-not $groupsByRole.ContainsKey($key)) { $groupsByRole[$key] = @() }
            $groupsByRole[$key] += $group.name
        }
    }
    $userNameByPk = @{}
    foreach ($user in $users) { $userNameByPk[[string]$user.pk] = $user.username }

    $applications = @(Get-AuthentikSeededObject -Type Applications -Connection $connection)
    $entitlements = @(Get-AuthentikSeededObject -Type Entitlements -Connection $connection)
    $mappings = @(Get-AuthentikSeededObject -Type ScopeMappings -Connection $connection)
    $tokens = @(Get-AuthentikSeededObject -Type Tokens -Connection $connection)
    $invitations = @(Get-AuthentikSeededObject -Type Invitations -Connection $connection)
    $policies = @(Get-AuthentikSeededObject -Type Policies -Connection $connection)
    $rules = @(Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)
    $transports = @(Get-AuthentikSeededObject -Type NotificationTransports -Connection $connection)
    $transportNameByPk = @{}
    foreach ($transport in $transports) { $transportNameByPk[[string]$transport.pk] = $transport.name }

    # Bindings tell which application each policy governs and who is admitted to what. Read
    # per seeded target, which is the side that has a filter.
    $boundTo = @{}
    $grantedTo = @{}
    $subjectOf = {
        param($binding)
        if ($binding.group) { if ($groupNameByPk.ContainsKey([string]$binding.group)) { return $groupNameByPk[[string]$binding.group] } else { return "group $($binding.group)" } }
        if ($binding.user) { if ($userNameByPk.ContainsKey([string]$binding.user)) { return $userNameByPk[[string]$binding.user] } else { return "user $($binding.user)" } }
        $null
    }
    $bindingTargets = @()
    foreach ($application in $applications) { $bindingTargets += @{ Uuid = [string]$application.pbm_uuid; Label = $application.slug } }
    foreach ($entitlement in $entitlements) { $bindingTargets += @{ Uuid = [string]$entitlement.pbm_uuid; Label = '{0}/{1}' -f $entitlement.app_slug, $entitlement.name } }
    foreach ($rule in $rules) { $bindingTargets += @{ Uuid = [string]$rule.pk; Label = $rule.name } }
    foreach ($bindingTarget in $bindingTargets) {
        try {
            $bindings = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                    -Query @{ target = $bindingTarget.Uuid } -Connection $connection -Paginate)
            foreach ($binding in $bindings) {
                if ($binding.policy) {
                    $key = [string]$binding.policy
                    if (-not $boundTo.ContainsKey($key)) { $boundTo[$key] = @() }
                    $boundTo[$key] += [PSCustomObject]@{ Slug = $bindingTarget.Label; Order = $binding.order; Enabled = $binding.enabled }
                    continue
                }
                $subject = & $subjectOf $binding
                if (-not $subject) { continue }
                if (-not $grantedTo.ContainsKey($bindingTarget.Uuid)) { $grantedTo[$bindingTarget.Uuid] = @() }
                $grantedTo[$bindingTarget.Uuid] += $subject
            }
        }
        catch {
            Write-Verbose "Could not read bindings for $($bindingTarget.Label): $($_.Exception.Message)"
        }
    }

    $attribute = { param($object, $name) if ($object.attributes -and $object.attributes.PSObject.Properties[$name]) { $object.attributes.$name } else { $null } }

    # PowerShell 7 hands an ISO timestamp back from JSON as a DateTime; 5.1 leaves the string.
    $asOffset = {
        param($value)
        if ($null -eq $value -or '' -eq $value) { return $null }
        if ($value -is [DateTimeOffset]) { return $value }
        if ($value -is [DateTime]) { return [DateTimeOffset]::new($value.ToUniversalTime(), [TimeSpan]::Zero) }
        try { return [DateTimeOffset]::Parse([string]$value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal) } catch { return $null }
    }

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
                    Roles       = (@($_.roles | ForEach-Object { if ($roleNameByPk.ContainsKey([string]$_)) { $roleNameByPk[[string]$_] } }) -join '; ')
                }
            })
        Roles             = @($roles | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name   = $_.name
                    Groups = (@($groupsByRole[[string]$_.pk]) -join '; ')
                }
            })
        Applications      = @($applications | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name         = $_.name
                    Slug         = $_.slug
                    ProviderType = $(if ($_.provider_obj) { $_.provider_obj.verbose_name } else { 'None' })
                    LaunchUrl    = $_.meta_launch_url
                    Hidden       = [bool]$_.meta_hide
                    GrantedTo    = (@($grantedTo[[string]$_.pbm_uuid]) -join '; ')
                }
            })
        ScopeMappings     = @($mappings | Sort-Object name | ForEach-Object {
                [PSCustomObject]@{
                    Name        = $_.name
                    Scope       = $_.scope_name
                    Description = $_.description
                }
            })
        Entitlements      = @($entitlements | Sort-Object app_slug, name | ForEach-Object {
                [PSCustomObject]@{
                    Application = $_.app_slug
                    Name        = $_.name
                    GrantedTo   = (@($grantedTo[[string]$_.pbm_uuid]) -join '; ')
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
                    Triggers   = $(
                        $ruleName = $_.name
                        (@($policies | Where-Object { @($boundTo[[string]$_.pk] | Where-Object { $_.Slug -eq $ruleName }).Count -gt 0 } | ForEach-Object { $_.name }) -join '; ')
                    )
                }
            })
        Tokens            = @($tokens | Sort-Object identifier | ForEach-Object {
                $expiresAt = $null
                if ($_.expiring) { $expiresAt = & $asOffset $_.expires }
                [PSCustomObject]@{
                    Identifier = $_.identifier
                    User       = $(if ($_.user_obj) { $_.user_obj.username } else { $_.user })
                    Intent     = $_.intent
                    Expires    = $(if ($expiresAt) { $expiresAt.UtcDateTime } else { $null })
                    Expired    = ($null -ne $expiresAt -and $expiresAt -lt [DateTimeOffset]::UtcNow)
                }
            })
        Invitations       = @($invitations | Sort-Object name | ForEach-Object {
                $expiresAt = & $asOffset $_.expires
                [PSCustomObject]@{
                    Name      = $_.name
                    Expires   = $(if ($expiresAt) { $expiresAt.UtcDateTime } else { $null })
                    SingleUse = [bool]$_.single_use
                }
            })
    }

    switch ($OutputFormat) {
        'Console' {
            Write-TestMessage -Message "Authentik Test Environment Report ($($connection.BaseUrl))" -Type Header
            foreach ($section in $script:AuthentikReportSections) {
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
            foreach ($section in $script:AuthentikReportSections) {
                $file = Join-Path -Path $OutputPath -ChildPath "AuthentikLab$section.csv"
                $report.$section | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
            }
            Write-Verbose "Wrote $($script:AuthentikReportSections.Count) CSV files to $OutputPath"
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
            $fragments = foreach ($section in $script:AuthentikReportSections) {
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
