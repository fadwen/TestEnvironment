function New-AuthentikOutpost {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded outposts from Data\AuthentikOutposts.csv, carrying the seeded providers
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$OutpostName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikOutposts.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($OutpostName) {
        $rows = @($rows | Where-Object { $OutpostName -contains $_.Name })
        $unknown = @($OutpostName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalOutposts   = $rows.Count
        CreatedOutposts = 0
        UpdatedOutposts = 0
        Outposts        = @()
        Errors          = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Outposts -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    # Each application's provider, with the type the outpost list reports, so a provider of
    # the wrong kind is caught before the API refuses it less clearly.
    $providerBySlug = @{}
    foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
        if ($application.provider) {
            $component = if ($application.provider_obj) { [string]$application.provider_obj.component } else { '' }
            $providerBySlug[[string]$application.slug] = @{ Pk = [int]$application.provider; Component = $component }
        }
    }
    $componentOfType = @{ proxy = 'ak-provider-proxy-form'; ldap = 'ak-provider-ldap-form'; radius = 'ak-provider-radius-form'; rac = 'ak-provider-rac-form' }

    $outposts = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, "Create Authentik $($row.Type) outpost")) { continue }

        try {
            $providers = @()
            $carried = @()
            foreach ($applicationKey in @($row.Applications -split ';' | Where-Object { $_ })) {
                $slug = '{0}-{1}' -f $marker.SlugPrefix, $applicationKey
                if (-not $providerBySlug.ContainsKey($slug)) {
                    $message = "Outpost '$name' names application '$slug', which does not exist or has no provider. Skipped."
                    $result.Errors += $message
                    Write-Warning $message
                    continue
                }
                $provider = $providerBySlug[$slug]
                if ($provider.Component -and $componentOfType.ContainsKey($row.Type) -and $provider.Component -ne $componentOfType[$row.Type]) {
                    $message = "Outpost '$name' is a $($row.Type) outpost and cannot carry the provider of '$slug'. Skipped."
                    $result.Errors += $message
                    Write-Warning $message
                    continue
                }
                $providers += $provider.Pk
                $carried += $slug
            }

            $body = @{
                name      = $name
                type      = $row.Type
                providers = $providers
                config    = @{ authentik_host = $connection.BaseUrl; log_level = 'info' }
            }

            $outpost = $null
            if ($existingByName.ContainsKey($name)) {
                $outpost = Invoke-AuthentikRequest -Method PATCH -Path "/outposts/instances/$($existingByName[$name].pk)/" -Body $body -Connection $connection
                $result.UpdatedOutposts++
                Write-Verbose "Updated outpost $name"
            }
            else {
                $outpost = Invoke-AuthentikRequest -Method POST -Path '/outposts/instances/' -Body $body -Connection $connection
                $result.CreatedOutposts++
                Write-Verbose "Created outpost $name"
            }

            $outposts.Add([PSCustomObject]@{
                    Id           = [string]$outpost.pk
                    Key          = $row.Name
                    Name         = $name
                    Type         = $row.Type
                    Applications = $carried
                    Deployed     = $false
                })
        }
        catch {
            $message = "Failed to create outpost '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Outposts = $outposts.ToArray()

    Write-Verbose ("Outposts: $($result.CreatedOutposts) created, $($result.UpdatedOutposts) updated, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
