function New-ADTestDnsZone {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seed's own DNS zones and the records in them, so the seeded computers resolve
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipDeviceRecords,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $seed = Get-ADTestSeedMarker
    $domain = Get-ADTestDomain
    $zone = Get-ADTestSeedZone -Marker $seed -Domain $domain

    $result = [PSCustomObject]@{
        DnsAvailable  = $true
        ZonesCreated  = 0
        ZonesExisting = 0
        DeviceRecords = 0
        ExtraRecords  = 0
        Zones         = @()
        Errors        = @()
    }

    try {
        Import-Module DnsServer -ErrorAction Stop -Verbose:$false
    }
    catch {
        $result.DnsAvailable = $false
        Write-Warning ('The DnsServer module is not available, so no zone is created and the ' +
            "seeded computers will not resolve: $($_.Exception.Message)")
        if ($PassThru) { return $result }
        return
    }

    # The DnsServer cmdlets default to the local machine, which is only the right answer when
    # this runs on a domain controller. The connection already knows which one to talk to.
    $dnsTarget = @{}
    if ($script:ADConnection -and $script:ADConnection.PSObject.Properties['Server'] -and $script:ADConnection.Server) {
        $dnsTarget['ComputerName'] = $script:ADConnection.Server
    }

    # --- the zones ---------------------------------------------------------------------
    $ready = @{}
    foreach ($entry in @(
            @{ Name = $zone.Forward; Kind = 'Forward' }
            @{ Name = $zone.Reverse; Kind = 'Reverse' })) {
        if (-not $PSCmdlet.ShouldProcess($entry.Name, "Create $($entry.Kind.ToLowerInvariant()) DNS zone")) { continue }
        try {
            $existing = Get-DnsServerZone -Name $entry.Name @dnsTarget -ErrorAction SilentlyContinue
            if ($existing) {
                # Present already: ours only if it carries the tag. Anything else is somebody's
                # zone that happens to share the name, and this module does not touch it.
                $zoneObject = Get-ADTestDnsZoneObject -ZoneName $entry.Name -DomainDN $domain.DomainDN
                if ($zoneObject -and $zoneObject.adminDescription -eq $seed.Tag) {
                    $result.ZonesExisting++
                }
                else {
                    throw ("A zone named $($entry.Name) already exists and does not carry " +
                        "$($seed.Tag) in adminDescription, so this module cannot prove it created it. Leaving it alone.")
                }
            }
            else {
                if ($entry.Kind -eq 'Forward') {
                    $null = Add-DnsServerPrimaryZone -Name $entry.Name -ReplicationScope 'Domain' @dnsTarget -ErrorAction Stop
                }
                else {
                    $null = Add-DnsServerPrimaryZone -NetworkId $zone.NetworkId -ReplicationScope 'Domain' @dnsTarget -ErrorAction Stop
                }
                $result.ZonesCreated++
                Write-Verbose "Created DNS zone $($entry.Name)"

                # Stamped so teardown can prove it. Without the tag the zone would be
                # removable only by its name, which is the rule this provider does not use.
                $zoneObject = Get-ADTestDnsZoneObject -ZoneName $entry.Name -DomainDN $domain.DomainDN
                if ($zoneObject) {
                    Set-ADObject -Identity $zoneObject.DistinguishedName -Replace @{ adminDescription = $seed.Tag } -ErrorAction Stop
                }
                else {
                    Write-Warning ("Created $($entry.Name) but could not find its directory object to tag it. " +
                        'Teardown will not remove it; remove it by hand.')
                }
            }
            $ready[$entry.Kind] = $entry.Name
            $result.Zones += [PSCustomObject]@{ Name = $entry.Name; Kind = $entry.Kind }
        }
        catch {
            $message = "DNS zone '$($entry.Name)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    # --- a record for every addressed device ---------------------------------------------
    if (-not $SkipDeviceRecords -and $ready.ContainsKey('Forward')) {
        $devicePath = Join-Path -Path (Get-ADTestDataPath) -ChildPath 'ADDevices.csv'
        $devices = @(Import-Csv -Path $devicePath -Encoding UTF8 | Where-Object { $_.IPAddress })
        $index = 0
        foreach ($device in $devices) {
            $index++
            $recordName = ('{0}{1}' -f $seed.Prefix, $device.DeviceName).ToLowerInvariant()
            Write-TestProgress -Activity 'Writing device DNS records' -Status "$index of $($devices.Count): $recordName" `
                -PercentComplete ([int](100 * $index / [Math]::Max(1, $devices.Count))) -ShowProgress:$ShowProgress
            if (-not $PSCmdlet.ShouldProcess("$recordName ($($device.IPAddress))", 'Create DNS A record')) { continue }
            try {
                $already = Get-DnsServerResourceRecord -ZoneName $ready.Forward -Name $recordName -RRType A @dnsTarget -ErrorAction SilentlyContinue
                if ($already) { continue }
                # -CreatePtr writes the reverse record too, which is why the reverse zone is
                # created first; without it the A record is written and the PTR is silently not.
                $null = Add-DnsServerResourceRecordA -ZoneName $ready.Forward -Name $recordName `
                    -IPv4Address $device.IPAddress -CreatePtr @dnsTarget -ErrorAction Stop
                $result.DeviceRecords++
            }
            catch {
                $message = "DNS record '$recordName': $($_.Exception.Message)"
                $result.Errors += $message
                Write-Error $message
            }
        }
        Write-TestProgress -Activity 'Writing device DNS records' -Completed -ShowProgress:$ShowProgress
    }

    # --- the records that are not a device ------------------------------------------------
    $recordPath = Join-Path -Path (Get-ADTestDataPath) -ChildPath 'ADDnsRecords.csv'
    foreach ($row in @(Import-Csv -Path $recordPath -Encoding UTF8)) {
        if (-not $ready.ContainsKey($row.Zone)) { continue }
        $zoneName = $ready[$row.Zone]
        # {prefix} and {zone} become the session's prefix and the forward zone, so an alias
        # target is a seeded computer's real name.
        $values = @(($row.Data -split ';') | Where-Object { $_ } | ForEach-Object {
                $_.Replace('{prefix}', $seed.Prefix.ToLowerInvariant()).Replace('{zone}', $ready.Forward)
            })
        if (-not $PSCmdlet.ShouldProcess("$($row.Name) $($row.Type) in $zoneName", 'Create DNS record')) { continue }
        try {
            $already = Get-DnsServerResourceRecord -ZoneName $zoneName -Name $row.Name -RRType $row.Type @dnsTarget -ErrorAction SilentlyContinue
            if ($already) { continue }
            foreach ($value in $values) {
                switch ($row.Type) {
                    'A' { $null = Add-DnsServerResourceRecordA -ZoneName $zoneName -Name $row.Name -IPv4Address $value @dnsTarget -ErrorAction Stop }
                    'CNAME' { $null = Add-DnsServerResourceRecordCName -ZoneName $zoneName -Name $row.Name -HostNameAlias $value @dnsTarget -ErrorAction Stop }
                    'TXT' { $null = Add-DnsServerResourceRecord -Txt -ZoneName $zoneName -Name $row.Name -DescriptiveText $value @dnsTarget -ErrorAction Stop }
                    'PTR' { $null = Add-DnsServerResourceRecordPtr -ZoneName $zoneName -Name $row.Name -PtrDomainName $value @dnsTarget -ErrorAction Stop }
                    default { throw "Unknown record type '$($row.Type)'." }
                }
                $result.ExtraRecords++
            }
        }
        catch {
            $message = "DNS record '$($row.Name)' ($($row.Type)) in ${zoneName}: $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-Verbose ("DNS: $($result.ZonesCreated) zones created, $($result.DeviceRecords) device records, " +
        "$($result.ExtraRecords) other records, $($result.Errors.Count) problems")
    if ($PassThru) { return $result }
}
