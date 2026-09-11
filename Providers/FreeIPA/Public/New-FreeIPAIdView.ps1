function New-FreeIPAIdView {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded ID views and overrides from Data\FreeIPAIdViews.csv and Data\FreeIPAIdOverrides.csv, and applies them to hosts
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$ViewName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $dataPath = Get-FreeIPADataPath

    $viewPath = Join-Path -Path $dataPath -ChildPath 'FreeIPAIdViews.csv'
    $viewRows = @(Import-Csv -Path $viewPath -Encoding UTF8)
    $overrideRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPAIdOverrides.csv') -Encoding UTF8)
    if ($ViewName) {
        $viewRows = @($viewRows | Where-Object { $ViewName -contains $_.Name })
        $unknown = @($ViewName | Where-Object { $viewRows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $viewPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalViews       = $viewRows.Count
        CreatedViews     = 0
        UpdatedViews     = 0
        OverridesCreated = 0
        OverridesUpdated = 0
        HostsApplied     = 0
        Views            = @()
        Errors           = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }
    $record = { param($problem) $result.Errors += $problem; Write-Error $problem }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type IdViews -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    $views = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $viewRows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA ID view')) { continue }
        try {
            $options = @{ description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim() }
            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'idview_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedViews++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'idview_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedViews++
                Write-Verbose "Created ID view $name"
            }

            # Overrides inside the view. A user is anchored by login, a group by its name in
            # the realm, and only the fields the row fills are overridden.
            foreach ($override in ($overrideRows | Where-Object { $_.View -eq $row.Name })) {
                $isUser = $override.Kind -eq 'User'
                $anchor = if ($isUser) { $override.Anchor } else { Resolve-FreeIPASeedName -Key $override.Anchor -Marker $marker -Connection $connection }
                $label = '{0} override for {1} in {2}' -f $override.Kind.ToLowerInvariant(), $anchor, $name
                if (-not $PSCmdlet.ShouldProcess($label, 'Create FreeIPA ID override')) { continue }

                $fields = @{}
                if ($isUser) {
                    if ($override.Login) { $fields['uid'] = $override.Login }
                    if ($override.Uid -match '^\d+$') { $fields['uidnumber'] = [int]$override.Uid }
                    if ($override.Gid -match '^\d+$') { $fields['gidnumber'] = [int]$override.Gid }
                    if ($override.Shell) { $fields['loginshell'] = $override.Shell }
                    if ($override.HomeDirectory) { $fields['homedirectory'] = $override.HomeDirectory }
                    if ($override.Gecos) { $fields['gecos'] = $override.Gecos }
                }
                else {
                    if ($override.Login) { $fields['cn'] = $override.Login }
                    if ($override.Gid -match '^\d+$') { $fields['gidnumber'] = [int]$override.Gid }
                }
                if ($override.Description) { $fields['description'] = $override.Description }

                $noun = if ($isUser) { 'idoverrideuser' } else { 'idoverridegroup' }
                $shown = Invoke-FreeIPARequest -Method "${noun}_show" -Arguments @($name, $anchor) -Connection $connection -IgnoreError 'NotFound'
                if ($shown) {
                    $null = Invoke-FreeIPARequest -Method "${noun}_mod" -Arguments @($name, $anchor) -Options $fields -Connection $connection -IgnoreError 'EmptyModlist'
                    $result.OverridesUpdated++
                }
                else {
                    $null = Invoke-FreeIPARequest -Method "${noun}_add" -Arguments @($name, $anchor) -Options $fields -Connection $connection
                    $result.OverridesCreated++
                }
            }

            $targets = @{ host = @(& $resolve $row.Hosts 'Host'); hostgroup = @(& $resolve $row.Hostgroups 'Name') }
            $total = @($targets.Values | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum
            if ($total -gt 0 -and $PSCmdlet.ShouldProcess($name, "Apply to $total host(s) or host group(s)")) {
                $outcome = Add-FreeIPAMember -Method 'idview_apply' -Name $name -Members $targets -Connection $connection
                $result.HostsApplied += $outcome.Completed
                foreach ($problem in $outcome.Errors) { & $record $problem }
            }

            $views.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Overrides = @($overrideRows | Where-Object { $_.View -eq $row.Name }).Count })
        }
        catch { & $record "Failed to create ID view '$name': $($_.Exception.Message)" }
    }

    $result.Views = $views.ToArray()
    Write-Verbose "ID views: $($result.CreatedViews) created, $($result.UpdatedViews) updated, $($result.OverridesCreated) overrides, $($result.HostsApplied) applied, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
