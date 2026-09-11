function New-FreeIPANetgroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded FreeIPA netgroups from Data\FreeIPANetgroups.csv, with their members
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$NetgroupName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPANetgroups.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($NetgroupName) {
        $rows = @($rows | Where-Object { $NetgroupName -contains $_.Name })
        $unknown = @($NetgroupName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalNetgroups     = $rows.Count
        CreatedNetgroups   = 0
        UpdatedNetgroups   = 0
        MembershipsApplied = 0
        Netgroups          = @()
        Errors             = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Netgroups -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }

    $netgroups = [System.Collections.Generic.List[object]]::new()
    $created = @{}

    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA netgroup')) { continue }

        try {
            $options = @{ description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim() }
            if ($row.UserCategory) { $options['usercategory'] = $row.UserCategory }
            if ($row.HostCategory) { $options['hostcategory'] = $row.HostCategory }

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'netgroup_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedNetgroups++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'netgroup_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedNetgroups++
                Write-Verbose "Created netgroup $name"
            }
            $created[$row.Name] = $name
            $netgroups.Add([PSCustomObject]@{ Key = $row.Name; Name = $name })
        }
        catch {
            $message = "Failed to create netgroup '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    # Members second, once every netgroup a row could name exists.
    foreach ($row in $rows) {
        if (-not $created.ContainsKey($row.Name)) { continue }
        $name = $created[$row.Name]
        $members = @{
            user      = @(& $split $row.Users)
            group     = @(& $resolve $row.Groups 'Name')
            host      = @(& $resolve $row.Hosts 'Host')
            hostgroup = @(& $resolve $row.Hostgroups 'Name')
            netgroup  = @(& $resolve $row.Netgroups 'Name')
        }
        $total = @($members.Values | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum
        if ($total -eq 0) { continue }
        if (-not $PSCmdlet.ShouldProcess($name, "Add $total member(s)")) { continue }
        try {
            $outcome = Add-FreeIPAMember -Method 'netgroup_add_member' -Name $name -Members $members -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { $result.Errors += $problem; Write-Error $problem }
        }
        catch {
            $message = "Failed to add members to netgroup '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Netgroups = $netgroups.ToArray()
    Write-Verbose "Netgroups: $($result.CreatedNetgroups) created, $($result.UpdatedNetgroups) updated, $($result.MembershipsApplied) memberships, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
