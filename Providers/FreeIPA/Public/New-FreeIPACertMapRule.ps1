function New-FreeIPACertMapRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded certificate identity mapping rules from Data\FreeIPACertMapRules.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RuleName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPACertMapRules.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($RuleName) {
        $rows = @($rows | Where-Object { $RuleName -contains $_.Name })
        $unknown = @($RuleName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules   = $rows.Count
        CreatedRules = 0
        UpdatedRules = 0
        Rules        = @()
        Errors       = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type CertMapRules -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    # The seed domain appears in a match rule escaped for a regular expression, so the
    # realm's domain goes in escaped the same way; {realm} is the realm's own name, for the
    # rule that matches the certificates its CA issued.
    $substitute = {
        param($text)
        ([string]$text).Replace([regex]::Escape($script:FreeIPADefaultSeedDomain), [regex]::Escape($connection.Domain)).Replace('{realm}', [regex]::Escape([string]$connection.Realm))
    }

    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA certificate mapping rule')) { continue }
        try {
            $options = @{
                description          = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()
                ipacertmapmatchrule  = & $substitute $row.MatchRule
                ipacertmapmaprule    = $row.MapRule
            }
            if ($row.Priority -match '^\d+$') { $options['ipacertmappriority'] = [int]$row.Priority }

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'certmaprule_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedRules++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'certmaprule_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedRules++
                Write-Verbose "Created certificate mapping rule $name"
            }

            if ($row.Enabled -eq 'FALSE') {
                $null = Invoke-FreeIPARequest -Method 'certmaprule_disable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyInactive'
            }
            elseif ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'certmaprule_enable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyActive'
            }

            $rules.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Enabled = ($row.Enabled -ne 'FALSE'); Priority = $row.Priority })
        }
        catch {
            $message = "Failed to create certificate mapping rule '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Rules = $rules.ToArray()
    Write-Verbose "Certificate mapping rules: $($result.CreatedRules) created, $($result.UpdatedRules) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
