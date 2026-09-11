function New-FreeIPADnsZone {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seed's own DNS zones and the records in them from Data\FreeIPADnsRecords.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipRecords,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $zone = Get-FreeIPASeedZone -Marker $marker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPADnsRecords.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    $result = [PSCustomObject]@{
        DnsEnabled     = $true
        ZonesCreated   = 0
        ZonesExisting  = 0
        RecordsCreated = 0
        RecordsUpdated = 0
        Zones          = @()
        Errors         = @()
    }

    $enabled = Invoke-FreeIPARequest -Method 'dns_is_enabled' -Connection $connection
    if (-not ($enabled -and $enabled.result -eq $true)) {
        $result.DnsEnabled = $false
        Write-Warning 'The realm has no DNS server, so no zone is created; the hosts will be records without addresses.'
        if ($PassThru) { return $result }
        return
    }

    $zones = [System.Collections.Generic.List[object]]::new()
    $ready = @{}
    foreach ($entry in @(
            @{ Name = $zone.Forward; Kind = 'Forward'; Options = @{ idnssoarname = $zone.Contact; idnsallowdynupdate = $false } }
            @{ Name = $zone.Reverse; Kind = 'Reverse'; Options = @{ idnssoarname = $zone.Contact; name_from_ip = $zone.Subnet } })) {
        if (-not $PSCmdlet.ShouldProcess($entry.Name, "Create FreeIPA $($entry.Kind.ToLowerInvariant()) DNS zone")) { continue }
        try {
            $shown = Invoke-FreeIPARequest -Method 'dnszone_show' -Arguments $entry.Name -Connection $connection -IgnoreError 'NotFound'
            if ($shown -and $shown.result) {
                $contact = ConvertFrom-FreeIPADnsName -Value $shown.result.idnssoarname
                if ($contact -ne $zone.Contact) {
                    throw "Zone $($entry.Name) already exists with the contact '$contact', which is not the seed's; it is left alone."
                }
                $result.ZonesExisting++
            }
            else {
                # The reverse zone is named from the subnet by the server, so its name is
                # not an argument; the forward zone's is.
                $arguments = @()
                if ($entry.Kind -eq 'Forward') { $arguments = @($entry.Name) }
                $null = Invoke-FreeIPARequest -Method 'dnszone_add' -Arguments $arguments -Options $entry.Options -Connection $connection
                $result.ZonesCreated++
                Write-Verbose "Created DNS zone $($entry.Name)"
            }
            $ready[$entry.Kind] = $entry.Name
            $zones.Add([PSCustomObject]@{ Name = $entry.Name; Kind = $entry.Kind })
        }
        catch {
            $message = "Failed to create DNS zone '$($entry.Name)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    if (-not $SkipRecords) {
        # {prefix} and {zone} in the data become the session's prefix and the forward zone,
        # so an alias target is a seeded host's real name.
        $substitute = { param($text) ([string]$text).Replace('{prefix}', $marker.NamePrefix).Replace('{zone}', $zone.Forward) }
        foreach ($row in $rows) {
            if (-not $ready.ContainsKey($row.Zone)) { continue }
            $zoneName = $ready[$row.Zone]
            $attribute = '{0}record' -f $row.Type.ToLowerInvariant()
            $values = [object[]]@(($row.Data -split ';') | Where-Object { $_ } | ForEach-Object { & $substitute $_ })
            if (-not $PSCmdlet.ShouldProcess("$($row.Name) $($row.Type) in $zoneName", 'Create FreeIPA DNS record')) { continue }
            try {
                $options = @{}
                $options[$attribute] = $values
                $shown = Invoke-FreeIPARequest -Method 'dnsrecord_show' -Arguments @($zoneName, $row.Name) -Connection $connection -IgnoreError 'NotFound'
                if ($shown -and $shown.result) {
                    $null = Invoke-FreeIPARequest -Method 'dnsrecord_mod' -Arguments @($zoneName, $row.Name) -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                    $result.RecordsUpdated++
                }
                else {
                    $null = Invoke-FreeIPARequest -Method 'dnsrecord_add' -Arguments @($zoneName, $row.Name) -Options $options -Connection $connection
                    $result.RecordsCreated++
                    Write-Verbose "Created DNS record $($row.Name) $($row.Type) in $zoneName"
                }
            }
            catch {
                $message = "Failed to create DNS record '$($row.Name)' ($($row.Type)) in ${zoneName}: $($_.Exception.Message)"
                $result.Errors += $message
                Write-Error $message
            }
        }
    }

    $result.Zones = $zones.ToArray()
    Write-Verbose "DNS: $($result.ZonesCreated) zones created, $($result.RecordsCreated) records created, $($result.RecordsUpdated) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
