function New-AuthentikEntitlement {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded application entitlements from Data\AuthentikEntitlements.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$EntitlementName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikEntitlements.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $keyOf = { param($row) '{0}/{1}' -f $row.Application, $row.Name }

    if ($EntitlementName) {
        $rows = @($rows | Where-Object { $EntitlementName -contains (& $keyOf $_) })
        $unknown = @($EntitlementName | Where-Object { @($rows | ForEach-Object { & $keyOf $_ }) -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalEntitlements   = $rows.Count
        CreatedEntitlements = 0
        UpdatedEntitlements = 0
        Entitlements        = @()
        Errors              = @()
    }

    $applicationBySlug = @{}
    foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
        $applicationBySlug[[string]$application.slug] = $application
    }

    $existingByKey = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Entitlements -Connection $connection)) {
        if ($existing.attributes.PSObject.Properties['labKey']) { $existingByKey[[string]$existing.attributes.labKey] = $existing }
    }

    $entitlements = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $key = & $keyOf $row
        $name = '{0}{1}' -f $marker.Prefix, $row.Name
        $slug = '{0}-{1}' -f $marker.SlugPrefix, $row.Application

        if (-not $PSCmdlet.ShouldProcess("$name on $slug", 'Create Authentik application entitlement')) { continue }

        try {
            if (-not $applicationBySlug.ContainsKey($slug)) {
                $message = "Entitlement '$key' belongs to application '$slug', which does not exist. Skipped."
                $result.Errors += $message
                Write-Warning $message
                continue
            }
            $application = $applicationBySlug[$slug]

            $attributes = [ordered]@{}
            $attributes[$marker.Attribute] = $marker.Tag
            $attributes['labKey'] = $key

            $body = @{
                name       = $name
                app        = [string]$application.pk
                attributes = $attributes
            }

            $entitlement = $null
            if ($existingByKey.ContainsKey($key)) {
                $entitlement = Invoke-AuthentikRequest -Method PATCH -Path "/core/application_entitlements/$($existingByKey[$key].pbm_uuid)/" -Body $body -Connection $connection
                $result.UpdatedEntitlements++
                Write-Verbose "Updated entitlement $key"
            }
            else {
                $entitlement = Invoke-AuthentikRequest -Method POST -Path '/core/application_entitlements/' -Body $body -Connection $connection
                $result.CreatedEntitlements++
                Write-Verbose "Created entitlement $key"
            }

            $entitlements.Add([PSCustomObject]@{
                    PbmUuid     = [string]$entitlement.pbm_uuid
                    Key         = $key
                    Name        = $name
                    Application = $slug
                })
        }
        catch {
            $message = "Failed to create entitlement '$key': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Entitlements = $entitlements.ToArray()

    Write-Verbose ("Entitlements: $($result.CreatedEntitlements) created, $($result.UpdatedEntitlements) updated, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
