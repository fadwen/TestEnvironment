function New-OktaNetworkZone {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded network zones that policies condition on
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$ZoneName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaDataPath) 'OktaNetworkZones.csv') -Encoding UTF8)
    if ($ZoneName) {
        $rows = @($rows | Where-Object { $ZoneName -contains $_.Name })
        $unknown = @($ZoneName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No network zone definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalZones    = $rows.Count
        CreatedZones  = 0
        ExistingZones = 0
        Zones         = @()
        Errors        = @()
    }

    $existingZones = @(Invoke-OktaRequest -Method GET -Path '/api/v1/zones' -Query @{ limit = 200 } -Paginate)
    $zones = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, "Create Okta network zone ($($row.Usage))")) { continue }

        try {
            $existing = @($existingZones | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $zone = $existing[0]
                $result.ExistingZones++
                Write-Verbose "Reusing network zone $name"
            }
            else {
                # A CIDR and a bare range are different gateway types, and Okta rejects the
                # wrong one, so the shape is inferred from the value rather than configured.
                $gateways = @(
                    foreach ($value in @($row.Gateways -split ';' | Where-Object { $_ })) {
                        @{ type = $(if ($value -like '*-*') { 'RANGE' } else { 'CIDR' }); value = $value }
                    }
                )

                $body = [ordered]@{
                    type     = $row.Type
                    name     = $name
                    status   = 'ACTIVE'
                    usage    = $row.Usage
                    gateways = $gateways
                }

                $zone = Invoke-OktaRequest -Method POST -Path '/api/v1/zones' -Body $body
                $result.CreatedZones++
                Write-Verbose "Created network zone $name"
            }

            $zones.Add([PSCustomObject]@{
                Id    = $zone.id
                Key   = $row.Name
                Name  = $name
                Usage = $row.Usage
            })
        }
        catch {
            $message = "Failed to create network zone '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Zones = $zones.ToArray()

    if ($PassThru) { return $result }
}
