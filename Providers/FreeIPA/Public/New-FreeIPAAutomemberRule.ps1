function New-FreeIPAAutomemberRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded automember rules from Data\FreeIPAAutomemberRules.csv and rebuilds the seeded entries against them
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Target,

        [Parameter()]
        [switch]$SkipRebuild,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAAutomemberRules.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($Target) {
        $rows = @($rows | Where-Object { $Target -contains $_.Target })
        $unknown = @($Target | Where-Object { $rows.Target -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules        = $rows.Count
        CreatedRules      = 0
        UpdatedRules      = 0
        ConditionsApplied = 0
        EntriesRebuilt    = 0
        Rules             = @()
        Errors            = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { [string]$value } }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type AutomemberRules -Connection $connection)) { $existing['{0}/{1}' -f $entry.automembertype, (& $first $entry.cn)] = $entry }

    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Target -Marker $marker -Connection $connection
        $type = $row.Kind
        if (-not $PSCmdlet.ShouldProcess("$name ($type)", 'Create FreeIPA automember rule')) { continue }
        try {
            $options = @{ type = $type; description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim() }
            if ($existing.ContainsKey("$type/$name")) {
                $null = Invoke-FreeIPARequest -Method 'automember_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedRules++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'automember_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedRules++
                Write-Verbose "Created automember rule $name"
            }

            # One condition per call. A leading '!' is an exclusive regex; anything else is
            # inclusive. A condition that already exists is the normal answer on a re-run.
            foreach ($condition in (& $split $row.Conditions)) {
                $exclusive = $condition.StartsWith('!')
                $attribute, $pattern = $condition.TrimStart('!') -split '=', 2
                $conditionOptions = @{ type = $type; key = $attribute }
                if ($exclusive) { $conditionOptions['automemberexclusiveregex'] = [object[]]@($pattern) }
                else { $conditionOptions['automemberinclusiveregex'] = [object[]]@($pattern) }
                $outcome = Invoke-FreeIPARequest -Method 'automember_add_condition' -Arguments $name -Options $conditionOptions -Connection $connection
                if ($outcome -and $outcome.PSObject.Properties['completed']) { $result.ConditionsApplied += [int]$outcome.completed }
                foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
                    if ($failure -like '*already exists*') { continue }
                    $message = "Could not add a condition to '$name': $failure"
                    $result.Errors += $message
                    Write-Error $message
                }
            }

            $rules.Add([PSCustomObject]@{ Key = $row.Target; Name = $name; Type = $type; Conditions = @(& $split $row.Conditions) })
        }
        catch {
            $message = "Failed to create automember rule '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    # The rebuild, scoped to the module's own entries by name and in batches. A rebuild
    # without a list would walk every user or host in the realm.
    if (-not $SkipRebuild -and $rules.Count -gt 0) {
        $rebuilds = @()
        if (@($rules | Where-Object Type -eq 'group').Count -gt 0) {
            $logins = @(Get-FreeIPASeededObject -Type Users -Connection $connection | ForEach-Object { & $first $_.uid })
            $rebuilds += @{ Type = 'group'; Option = 'users'; Names = $logins }
        }
        if (@($rules | Where-Object Type -eq 'hostgroup').Count -gt 0) {
            $fqdns = @(Get-FreeIPASeededObject -Type Hosts -Connection $connection | ForEach-Object { & $first $_.fqdn })
            $rebuilds += @{ Type = 'hostgroup'; Option = 'hosts'; Names = $fqdns }
        }
        foreach ($rebuild in $rebuilds) {
            $names = @($rebuild.Names)
            if ($names.Count -eq 0) { continue }
            if (-not $PSCmdlet.ShouldProcess("$($names.Count) seeded $($rebuild.Option)", 'Rebuild automember membership')) { continue }
            for ($start = 0; $start -lt $names.Count; $start += 100) {
                $chunk = @($names[$start..([Math]::Min($start + 99, $names.Count - 1))])
                try {
                    $rebuildOptions = @{ type = $rebuild.Type }
                    $rebuildOptions[$rebuild.Option] = [object[]]$chunk
                    $null = Invoke-FreeIPARequest -Method 'automember_rebuild' -Options $rebuildOptions -Connection $connection
                    $result.EntriesRebuilt += $chunk.Count
                }
                catch {
                    $message = "Failed to rebuild $($chunk.Count) $($rebuild.Option): $($_.Exception.Message)"
                    $result.Errors += $message
                    Write-Error $message
                }
            }
        }
    }

    $result.Rules = $rules.ToArray()
    Write-Verbose "Automember: $($result.CreatedRules) rules created, $($result.UpdatedRules) updated, $($result.ConditionsApplied) conditions, $($result.EntriesRebuilt) entries rebuilt, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
