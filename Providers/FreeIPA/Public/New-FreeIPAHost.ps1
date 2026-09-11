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

    # A host with an address gets its A record, and its PTR, from FreeIPA on creation - but
    # only into the seed's own zone, and only if that zone exists. Without it (DNS skipped,
    # or a realm with no DNS) every host is a record without an address, as before. The
    # zone is looked up once, at the first host that needs it, so -WhatIf reads nothing.
    $zone = Get-FreeIPASeedZone -Marker $marker -Connection $connection
    $zoneReady = $null
    $zoneIsReady = {
        if ($null -eq $zoneReady) {
            $shownZone = Invoke-FreeIPARequest -Method 'dnszone_show' -Arguments $zone.Forward -Connection $connection -IgnoreError 'NotFound'
            $script:__zoneReady = [bool]($shownZone -and $shownZone.result)
            Set-Variable -Name zoneReady -Scope 1 -Value $script:__zoneReady
            Remove-Variable -Name __zoneReady -Scope Script
            if (-not $zoneReady) { Write-Warning "DNS zone $($zone.Forward) is not there, so the hosts are created without addresses." }
        }
        $zoneReady
    }

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
                # Force, so the realm's DNS is not consulted for a name it does not know. With
                # an address, FreeIPA writes the A record into the seed's zone and the PTR
                # into the seed's reverse zone; the realm's own zone is never touched.
                $options['force'] = $true
                if ($row.IPAddress -and (& $zoneIsReady)) { $options['ip_address'] = $row.IPAddress }
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
                    IPAddress  = $row.IPAddress
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
