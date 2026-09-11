function New-FreeIPAAutomount {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded automount location, maps and keys from Data\FreeIPAAutomount.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAAutomount.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    $result = [PSCustomObject]@{
        LocationsCreated = 0
        MapsCreated      = 0
        MapsUpdated      = 0
        KeysCreated      = 0
        KeysUpdated      = 0
        Keys             = @()
        Errors           = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type AutomountLocations -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    # The seed file names the NFS host against the seed domain with a prefix placeholder;
    # the seed's forward zone, where the host really lives, and the session's prefix go in.
    $zone = Get-FreeIPASeedZone -Marker $marker -Connection $connection
    $substitute = { param($text) ([string]$text).Replace('{prefix}', $marker.NamePrefix).Replace($script:FreeIPADefaultSeedDomain, $zone.Forward) }

    $keys = [System.Collections.Generic.List[object]]::new()

    foreach ($row in ($rows | Where-Object Kind -eq 'Location')) {
        $location = Resolve-FreeIPASeedName -Key $row.Location -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($location, 'Create FreeIPA automount location')) { continue }
        try {
            if (-not $existing.ContainsKey($location)) {
                $null = Invoke-FreeIPARequest -Method 'automountlocation_add' -Arguments $location -Connection $connection
                $result.LocationsCreated++
                Write-Verbose "Created automount location $location"
            }
        }
        catch {
            $message = "Failed to create automount location '$location': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    foreach ($row in ($rows | Where-Object Kind -eq 'Map')) {
        $location = Resolve-FreeIPASeedName -Key $row.Location -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess("$($row.Map) in $location", 'Create FreeIPA automount map')) { continue }
        try {
            $shown = Invoke-FreeIPARequest -Method 'automountmap_show' -Arguments @($location, $row.Map) -Connection $connection -IgnoreError 'NotFound'
            if ($shown) {
                $null = Invoke-FreeIPARequest -Method 'automountmap_mod' -Arguments @($location, $row.Map) -Options @{ description = $row.Description } -Connection $connection -IgnoreError 'EmptyModlist'
                $result.MapsUpdated++
            }
            else {
                # The mount point travels as 'key', the name the API gives what the CLI calls
                # --mount: it becomes the key of the entry in the parent map.
                $null = Invoke-FreeIPARequest -Method 'automountmap_add_indirect' -Arguments @($location, $row.Map) -Connection $connection -Options @{
                    key         = $row.MountPoint
                    description = $row.Description
                }
                $result.MapsCreated++
                Write-Verbose "Created automount map $($row.Map) in $location"
            }
        }
        catch {
            $message = "Failed to create automount map '$($row.Map)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    foreach ($row in ($rows | Where-Object Kind -eq 'Key')) {
        $location = Resolve-FreeIPASeedName -Key $row.Location -Marker $marker -Connection $connection
        $info = & $substitute $row.Info
        if (-not $PSCmdlet.ShouldProcess("$($row.Key) in $($row.Map) ($location)", 'Create FreeIPA automount key')) { continue }
        try {
            # A missing key answers EmptyResult rather than NotFound, unlike every other show.
            $shown = Invoke-FreeIPARequest -Method 'automountkey_show' -Arguments @($location, $row.Map) -Options @{ automountkey = $row.Key } -Connection $connection -IgnoreError 'NotFound', 'EmptyResult'
            if ($shown) {
                $null = Invoke-FreeIPARequest -Method 'automountkey_mod' -Arguments @($location, $row.Map) -Connection $connection -IgnoreError 'EmptyModlist' -Options @{
                    automountkey         = $row.Key
                    automountinformation = $info
                }
                $result.KeysUpdated++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'automountkey_add' -Arguments @($location, $row.Map) -Connection $connection -Options @{
                    automountkey         = $row.Key
                    automountinformation = $info
                }
                $result.KeysCreated++
                Write-Verbose "Created automount key $($row.Key) in $($row.Map)"
            }
            $keys.Add([PSCustomObject]@{ Location = $location; Map = $row.Map; Key = $row.Key; Info = $info })
        }
        catch {
            $message = "Failed to create automount key '$($row.Key)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Keys = $keys.ToArray()
    Write-Verbose "Automount: $($result.LocationsCreated) locations, $($result.MapsCreated) maps created, $($result.KeysCreated) keys created, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
