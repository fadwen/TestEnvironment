function New-OktaTrustedOrigin {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded trusted origins
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$OriginName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaDataPath) 'OktaTrustedOrigins.csv') -Encoding UTF8)
    if ($OriginName) {
        $rows = @($rows | Where-Object { $OriginName -contains $_.Name })
        $unknown = @($OriginName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No trusted origin definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalOrigins    = $rows.Count
        CreatedOrigins  = 0
        ExistingOrigins = 0
        Origins         = @()
        Errors          = @()
    }

    $existingOrigins = @(Invoke-OktaRequest -Method GET -Path '/api/v1/trustedOrigins' `
        -Query @{ limit = 200 } -Paginate)
    $origins = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Okta trusted origin')) { continue }

        try {
            $existing = @($existingOrigins | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $origin = $existing[0]
                $result.ExistingOrigins++
                Write-Verbose "Reusing trusted origin $name"
            }
            else {
                $scopes = @(
                    foreach ($scope in @($row.Scopes -split ';' | Where-Object { $_ })) {
                        @{ type = $scope }
                    }
                )

                $origin = Invoke-OktaRequest -Method POST -Path '/api/v1/trustedOrigins' -Body @{
                    name   = $name
                    origin = $row.Origin
                    scopes = $scopes
                }
                $result.CreatedOrigins++
                Write-Verbose "Created trusted origin $name"
            }

            $origins.Add([PSCustomObject]@{
                Id     = $origin.id
                Key    = $row.Name
                Name   = $name
                Origin = $row.Origin
                Scopes = @($row.Scopes -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create trusted origin '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Origins = $origins.ToArray()

    if ($PassThru) { return $result }
}
