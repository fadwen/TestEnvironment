function New-FreeIPAIdentityProvider {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded RADIUS proxies and external identity providers from Data\FreeIPAIdentityProviders.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$ProviderName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $zone = Get-FreeIPASeedZone -Marker $marker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAIdentityProviders.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($ProviderName) {
        $rows = @($rows | Where-Object { $ProviderName -contains $_.Name })
        $unknown = @($ProviderName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalProviders = $rows.Count
        CreatedProxies = 0
        UpdatedProxies = 0
        CreatedIdps    = 0
        UpdatedIdps    = 0
        Providers      = @()
        Errors         = @()
    }

    # {prefix} and {zone} in a server or client name become the session's prefix and the
    # seed's forward zone, so a proxy points at a seeded host's real name.
    $substitute = { param($text) ([string]$text).Replace('{prefix}', $marker.NamePrefix).Replace('{zone}', $zone.Forward) }
    $secret = { [System.Net.NetworkCredential]::new('', (New-TestPassword -Length 32)).Password }

    $existingProxies = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type RadiusProxies -Connection $connection)) { $existingProxies[[string](@($entry.cn)[0])] = $entry }
    $existingIdps = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type IdentityProviders -Connection $connection)) { $existingIdps[[string](@($entry.cn)[0])] = $entry }

    $providers = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        $kind = if ($row.Kind -eq 'Radius') { 'RADIUS proxy' } else { 'identity provider' }
        if (-not $PSCmdlet.ShouldProcess($name, "Create FreeIPA $kind")) { continue }
        try {
            switch ($row.Kind) {
                'Radius' {
                    $options = @{
                        description          = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()
                        ipatokenradiusserver = (& $substitute $row.Server)
                    }
                    if ($row.Timeout -match '^\d+$') { $options['ipatokenradiustimeout'] = [int]$row.Timeout }
                    if ($row.Retries -match '^\d+$') { $options['ipatokenradiusretries'] = [int]$row.Retries }
                    if ($row.UserMapAttribute) { $options['ipatokenusermapattribute'] = $row.UserMapAttribute }

                    if ($existingProxies.ContainsKey($name)) {
                        # The secret stays what it is: a re-run does not rotate what it never kept.
                        $null = Invoke-FreeIPARequest -Method 'radiusproxy_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                        $result.UpdatedProxies++
                    }
                    else {
                        $options['ipatokenradiussecret'] = & $secret
                        $null = Invoke-FreeIPARequest -Method 'radiusproxy_add' -Arguments $name -Options $options -Connection $connection
                        $result.CreatedProxies++
                        Write-Verbose "Created RADIUS proxy $name"
                    }
                }
                'Idp' {
                    $options = @{
                        ipaidpclientid = (& $substitute $row.ClientId)
                    }
                    if ($row.Scope) { $options['ipaidpscope'] = $row.Scope }
                    if ($row.Subject) { $options['ipaidpsub'] = $row.Subject }

                    if ($existingIdps.ContainsKey($name)) {
                        $null = Invoke-FreeIPARequest -Method 'idp_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                        $result.UpdatedIdps++
                    }
                    else {
                        # The provider template is only for creation: it fills the endpoints in.
                        $options['ipaidpprovider'] = $row.Provider
                        if ($row.Org) { $options['ipaidporg'] = $row.Org }
                        if ($row.BaseUrl) { $options['ipaidpbaseurl'] = (& $substitute $row.BaseUrl) }
                        $options['ipaidpclientsecret'] = & $secret
                        $null = Invoke-FreeIPARequest -Method 'idp_add' -Arguments $name -Options $options -Connection $connection
                        $result.CreatedIdps++
                        Write-Verbose "Created identity provider $name"
                    }
                }
                default { throw "Unknown kind '$($row.Kind)' on row '$($row.Name)'." }
            }
            $providers.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Kind = $row.Kind })
        }
        catch {
            $message = "Failed to create $kind '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Providers = $providers.ToArray()
    Write-Verbose "Identity providers: $($result.CreatedProxies) proxies and $($result.CreatedIdps) providers created, $($result.UpdatedProxies + $result.UpdatedIdps) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
