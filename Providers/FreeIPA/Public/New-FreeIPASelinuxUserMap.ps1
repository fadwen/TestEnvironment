function New-FreeIPASelinuxUserMap {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded SELinux user maps from Data\FreeIPASelinuxUserMaps.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$MapName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPASelinuxUserMaps.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($MapName) {
        $rows = @($rows | Where-Object { $MapName -contains $_.Name })
        $unknown = @($MapName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalMaps          = $rows.Count
        CreatedMaps        = 0
        UpdatedMaps        = 0
        MembershipsApplied = 0
        Maps               = @()
        Errors             = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $resolve = { param($keys, $kind) @(& $split $keys | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind $kind -Marker $marker -Connection $connection }) }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type SelinuxUserMaps -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    $maps = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA SELinux user map')) { continue }
        try {
            $options = @{
                ipaselinuxuser = $row.SelinuxUser
                description    = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()
            }
            if ($row.HbacRule) { $options['seealso'] = Resolve-FreeIPASeedName -Key $row.HbacRule -Marker $marker -Connection $connection }

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'selinuxusermap_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedMaps++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'selinuxusermap_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedMaps++
                Write-Verbose "Created SELinux user map $name"
            }

            if (-not $row.HbacRule) {
                foreach ($clause in @(
                        @{ Method = 'selinuxusermap_add_user'; Members = @{ user = @(& $split $row.Users); group = @(& $resolve $row.Groups 'Name') } }
                        @{ Method = 'selinuxusermap_add_host'; Members = @{ host = @(& $resolve $row.Hosts 'Host'); hostgroup = @(& $resolve $row.Hostgroups 'Name') } }
                    )) {
                    $outcome = Add-FreeIPAMember -Method $clause.Method -Name $name -Members $clause.Members -Connection $connection
                    $result.MembershipsApplied += $outcome.Completed
                    foreach ($problem in $outcome.Errors) { $result.Errors += $problem; Write-Error $problem }
                }
            }

            if ($row.Enabled -eq 'FALSE') {
                $null = Invoke-FreeIPARequest -Method 'selinuxusermap_disable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyInactive'
            }
            elseif ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'selinuxusermap_enable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyActive'
            }

            $maps.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; SelinuxUser = $row.SelinuxUser; Enabled = ($row.Enabled -ne 'FALSE') })
        }
        catch {
            $message = "Failed to create SELinux user map '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Maps = $maps.ToArray()
    Write-Verbose "SELinux maps: $($result.CreatedMaps) created, $($result.UpdatedMaps) updated, $($result.MembershipsApplied) memberships, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
