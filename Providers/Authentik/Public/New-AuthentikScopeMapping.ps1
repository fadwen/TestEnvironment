function New-AuthentikScopeMapping {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded OAuth2 scope mappings from Data\AuthentikScopeMappings.csv and attaches them to providers
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$MappingName,

        [Parameter()]
        [switch]$SkipProvider,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikScopeMappings.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($MappingName) {
        $rows = @($rows | Where-Object { $MappingName -contains $_.Name })
        $unknown = @($MappingName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalMappings    = $rows.Count
        CreatedMappings  = 0
        UpdatedMappings  = 0
        ProvidersUpdated = 0
        Mappings         = @()
        Errors           = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type ScopeMappings -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    $providerBySlug = @{}
    if (-not $SkipProvider) {
        foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
            if ($application.provider) { $providerBySlug[[string]$application.slug] = [string]$application.provider }
        }
    }

    $mappings = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name.Replace('-', ' ')

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik scope mapping')) { continue }

        try {
            $body = @{
                name        = $name
                scope_name  = $row.ScopeName
                description = $row.Description
                expression  = $row.Expression.Replace('`n', "`n")
            }

            $mapping = $null
            if ($existingByName.ContainsKey($name)) {
                $mapping = Invoke-AuthentikRequest -Method PATCH -Path "/propertymappings/provider/scope/$($existingByName[$name].pk)/" -Body $body -Connection $connection
                $result.UpdatedMappings++
                Write-Verbose "Updated scope mapping $name"
            }
            else {
                $mapping = Invoke-AuthentikRequest -Method POST -Path '/propertymappings/provider/scope/' -Body $body -Connection $connection
                $result.CreatedMappings++
                Write-Verbose "Created scope mapping $name"
            }

            $attached = @()
            if (-not $SkipProvider) {
                foreach ($applicationKey in @($row.Applications -split ';' | Where-Object { $_ })) {
                    $slug = '{0}-{1}' -f $marker.SlugPrefix, $applicationKey
                    if (-not $providerBySlug.ContainsKey($slug)) {
                        $message = "Scope mapping '$name' names application '$slug', which does not exist or has no provider. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # Only an OAuth2 provider has scope mappings. Reading it first keeps the
                    # standard openid, email and profile scopes it was created with.
                    $providerPk = $providerBySlug[$slug]
                    $provider = $null
                    try { $provider = Invoke-AuthentikRequest -Method GET -Path "/providers/oauth2/$providerPk/" -Connection $connection }
                    catch {
                        $message = "Scope mapping '$name' names application '$slug', whose provider is not OAuth2. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    $current = @($provider.property_mappings | ForEach-Object { [string]$_ })
                    if ($current -notcontains [string]$mapping.pk) {
                        $null = Invoke-AuthentikRequest -Method PATCH -Path "/providers/oauth2/$providerPk/" `
                            -Body @{ property_mappings = @($current + [string]$mapping.pk) } -Connection $connection
                        $result.ProvidersUpdated++
                    }
                    $attached += $slug
                }
            }

            $mappings.Add([PSCustomObject]@{
                    Id           = [string]$mapping.pk
                    Key          = $row.Name
                    Name         = $name
                    ScopeName    = $row.ScopeName
                    Applications = $attached
                })
        }
        catch {
            $message = "Failed to create scope mapping '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Mappings = $mappings.ToArray()

    Write-Verbose ("Scope mappings: $($result.CreatedMappings) created, $($result.UpdatedMappings) updated, " +
        "$($result.ProvidersUpdated) providers updated, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
