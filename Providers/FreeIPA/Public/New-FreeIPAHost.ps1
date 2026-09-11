function New-FreeIPAHost {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded FreeIPA hosts from Data\FreeIPAHosts.csv, in their host groups
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$HostName,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$SkipHostgroups,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAHosts.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($HostName) {
        $rows = @($rows | Where-Object { $HostName -contains $_.Name })
        $unknown = @($HostName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalHosts         = $rows.Count
        CreatedHosts       = 0
        UpdatedHosts       = 0
        MembershipsApplied = 0
        Hosts              = @()
        Errors             = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Hosts -Connection $connection)) {
        $existing[[string](@($entry.fqdn)[0])] = $entry
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }

    $hosts = [System.Collections.Generic.List[object]]::new()
    $created = @{}
    $membersOf = @{}
    $managedBy = @{}
    $index = 0

    foreach ($row in $rows) {
        $fqdn = Resolve-FreeIPASeedName -Key $row.Name -Kind Host -Marker $marker -Connection $connection
        $index++
        Write-TestProgress -Activity 'Seeding hosts' -Status "$index of $($rows.Count): $fqdn" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess($fqdn, 'Create FreeIPA host')) { continue }

        try {
            $options = @{
                description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()
                userclass   = [object[]]@(@($marker.Tag) + @(& $split $row.Class))
            }
            if ($row.OperatingSystem) { $options['nsosversion'] = $row.OperatingSystem }
            if ($row.Platform) { $options['nshardwareplatform'] = $row.Platform }
            if ($row.Locality) { $options['l'] = $row.Locality }
            if ($row.Location) { $options['nshostlocation'] = $row.Location }
            if ($row.MacAddress) { $options['macaddress'] = [object[]]@(& $split $row.MacAddress) }
            if ($row.SshPublicKey) { $options['ipasshpubkey'] = [object[]]@(& $split $row.SshPublicKey) }
            if ($row.AuthIndicator) { $options['krbprincipalauthind'] = [object[]]@(& $split $row.AuthIndicator) }

            if ($existing.ContainsKey($fqdn)) {
                $null = Invoke-FreeIPARequest -Method 'host_mod' -Arguments $fqdn -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedHosts++
                Write-Verbose "Updated host $fqdn"
            }
            else {
                # Force, so the realm's DNS is neither consulted nor written; a seeded host is
                # a record, not a machine with an address.
                $options['force'] = $true
                $null = Invoke-FreeIPARequest -Method 'host_add' -Arguments $fqdn -Options $options -Connection $connection
                $result.CreatedHosts++
                Write-Verbose "Created host $fqdn"
            }

            $created[$row.Name] = $fqdn
            if (-not $SkipHostgroups) {
                foreach ($groupKey in (& $split $row.Hostgroups)) {
                    if (-not $membersOf.ContainsKey($groupKey)) { $membersOf[$groupKey] = [System.Collections.Generic.List[string]]::new() }
                    $membersOf[$groupKey].Add($fqdn)
                }
            }
            if ($row.ManagedBy) { $managedBy[$fqdn] = $row.ManagedBy }

            $hosts.Add([PSCustomObject]@{
                    Key        = $row.Name
                    Name       = $fqdn
                    Class      = $row.Class
                    Hostgroups = @(& $split $row.Hostgroups)
                })
        }
        catch {
            $message = "Failed to create host '$fqdn': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-TestProgress -Activity 'Seeding hosts' -Completed -ShowProgress:$ShowProgress

    # Membership, one call per host group, in chunks a single request comfortably carries.
    foreach ($groupKey in ($membersOf.Keys | Sort-Object)) {
        $groupName = Resolve-FreeIPASeedName -Key $groupKey -Marker $marker -Connection $connection
        $members = @($membersOf[$groupKey])
        if (-not $PSCmdlet.ShouldProcess($groupName, "Add $($members.Count) member host(s)")) { continue }
        for ($start = 0; $start -lt $members.Count; $start += 100) {
            $chunk = @($members[$start..([Math]::Min($start + 99, $members.Count - 1))])
            try {
                $outcome = Invoke-FreeIPARequest -Method 'hostgroup_add_member' -Arguments $groupName -Connection $connection `
                    -Options @{ host = [object[]]$chunk }
                $result.MembershipsApplied += [int]$outcome.completed
                foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
                    if ($failure -like '*already a member*') { continue }
                    $message = "Could not add to host group '$groupName': $failure"
                    $result.Errors += $message
                    Write-Error $message
                }
            }
            catch {
                $message = "Failed to add members to host group '$groupName': $($_.Exception.Message)"
                $result.Errors += $message
                Write-Error $message
            }
        }
    }

    foreach ($fqdn in ($managedBy.Keys | Sort-Object)) {
        $managerKey = $managedBy[$fqdn]
        $managerFqdn = Resolve-FreeIPASeedName -Key $managerKey -Kind Host -Marker $marker -Connection $connection
        if (-not ($created.ContainsKey($managerKey) -or $existing.ContainsKey($managerFqdn))) {
            Write-Warning "Host '$fqdn' is managed by '$managerKey', which does not exist. Left unmanaged."
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($fqdn, "Managed by $managerFqdn")) { continue }
        try {
            $outcome = Invoke-FreeIPARequest -Method 'host_add_managedby' -Arguments $fqdn -Connection $connection `
                -Options @{ host = [object[]]@($managerFqdn) }
            foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
                if ($failure -like '*already a member*') { continue }
                $message = "Could not set the manager of '$fqdn': $failure"
                $result.Errors += $message
                Write-Error $message
            }
        }
        catch {
            $message = "Failed to set the manager of '$fqdn': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Hosts = $hosts.ToArray()

    Write-Verbose ("Hosts: $($result.CreatedHosts) created, $($result.UpdatedHosts) updated, " +
        "$($result.MembershipsApplied) memberships, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
