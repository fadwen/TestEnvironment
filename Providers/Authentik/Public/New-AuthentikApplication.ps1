function New-AuthentikApplication {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Authentik applications and the providers behind them
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$ApplicationName,

        [Parameter()]
        [switch]$SkipProvider,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikApplications.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($ApplicationName) {
        $rows = @($rows | Where-Object { $ApplicationName -contains $_.Name })
        $unknown = @($ApplicationName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalApplications   = $rows.Count
        CreatedApplications = 0
        UpdatedApplications = 0
        ProvidersCreated    = 0
        Applications        = @()
        Errors              = @()
    }

    # The seed URLs are written against a placeholder domain, substituted with the
    # connection's own so redirect URIs and launch URLs belong to whatever domain the users do.
    $substitute = {
        param($value)
        if ([string]::IsNullOrWhiteSpace($value)) { return $value }
        $value -replace [regex]::Escape($script:AuthentikDefaultSeedDomain), $connection.EmailDomain
    }

    $existingBySlug = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
        $existingBySlug[[string]$existing.slug] = $existing
    }
    $existingProviderByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Providers -Connection $connection)) {
        $existingProviderByName[[string]$existing.name] = $existing
    }

    $applications = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name
        $slug = '{0}-{1}' -f $marker.SlugPrefix, $row.Slug

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik application')) { continue }

        try {
            $providerPk = $null
            $providerType = if ($SkipProvider) { 'None' } else { $row.ProviderType }

            if ($providerType -ne 'None') {
                $providerName = '{0} Provider' -f $name

                if ($existingProviderByName.ContainsKey($providerName)) {
                    $providerPk = [int]$existingProviderByName[$providerName].pk
                    Write-Verbose "Reusing provider $providerName"
                }
                else {
                    $authorization = Get-AuthentikFlow -Designation authorization -Connection $connection
                    $invalidation = Get-AuthentikFlow -Designation invalidation -Connection $connection

                    # Provider-specific settings ride in one CSV cell. URLs in it are written
                    # against the seed domain like every other URL, and a list joins with a
                    # comma where the API wants one string.
                    $settings = ConvertFrom-AuthentikSetting -Text $row.Settings
                    foreach ($key in @($settings.Keys)) {
                        if ($settings[$key] -is [string]) { $settings[$key] = & $substitute $settings[$key] }
                    }

                    $provider = $null
                    switch ($providerType) {
                        'OAuth2' {
                            $redirect = & $substitute $row.RedirectUri
                            $mode = if ($redirect -match '[\*\[\]\(\)\$\^]') { 'regex' } else { 'strict' }
                            $provider = Invoke-AuthentikRequest -Method POST -Path '/providers/oauth2/' -Connection $connection -Body @{
                                name               = $providerName
                                authorization_flow = $authorization
                                invalidation_flow  = $invalidation
                                client_type        = $row.ClientType
                                redirect_uris      = @(@{ matching_mode = $mode; url = $redirect })
                            }
                        }
                        'Proxy' {
                            # internal_host is optional in the schema and required by the
                            # server in proxy mode: 'Internal host cannot be empty when forward
                            # auth is disabled'. It is the backend the proxy fronts, and stays
                            # as written because it is never a user-facing address.
                            $provider = Invoke-AuthentikRequest -Method POST -Path '/providers/proxy/' -Connection $connection -Body @{
                                name               = $providerName
                                authorization_flow = $authorization
                                invalidation_flow  = $invalidation
                                external_host      = (& $substitute $row.ExternalHost)
                                internal_host      = $row.InternalHost
                                mode               = 'proxy'
                            }
                        }
                        'SAML' {
                            # Signed responses need a keypair the seed owns; borrowing the
                            # instance's would sign lab assertions with a real key and leave
                            # teardown nothing it could remove.
                            $body = @{
                                name               = $providerName
                                authorization_flow = $authorization
                                invalidation_flow  = $invalidation
                                signing_kp         = (Get-AuthentikSigningKeypair -Connection $connection)
                            }
                            foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
                            $provider = Invoke-AuthentikRequest -Method POST -Path '/providers/saml/' -Connection $connection -Body $body
                        }
                        'LDAP' {
                            $body = @{
                                name               = $providerName
                                authorization_flow = $authorization
                                invalidation_flow  = $invalidation
                            }
                            foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
                            $provider = Invoke-AuthentikRequest -Method POST -Path '/providers/ldap/' -Connection $connection -Body $body
                        }
                        'RADIUS' {
                            # The shared secret is generated here and never written anywhere:
                            # a secret in a CSV is a secret in a repository.
                            $body = @{
                                name               = $providerName
                                authorization_flow = $authorization
                                invalidation_flow  = $invalidation
                                shared_secret      = (New-TestPassword)
                            }
                            foreach ($key in $settings.Keys) {
                                $body[$key] = if ($key -eq 'client_networks' -and $settings[$key] -is [array]) { $settings[$key] -join ',' } else { $settings[$key] }
                            }
                            $provider = Invoke-AuthentikRequest -Method POST -Path '/providers/radius/' -Connection $connection -Body $body
                        }
                        default { throw "Unknown provider type '$providerType' for '$($row.Name)'." }
                    }
                    $providerPk = [int]$provider.pk
                    $result.ProvidersCreated++
                    Write-Verbose "Created $providerType provider $providerName"
                }
            }

            $body = @{
                name               = $name
                slug               = $slug
                provider           = $providerPk
                meta_launch_url    = (& $substitute $row.LaunchUrl)
                meta_description   = '{0} {1}' -f $row.Description, $marker.Marker
                group              = $row.Group
                meta_hide          = ($row.Hidden -eq 'TRUE')
                policy_engine_mode = 'any'
            }
            if (-not $body.meta_launch_url) { $body.Remove('meta_launch_url') }

            $application = $null
            if ($existingBySlug.ContainsKey($slug)) {
                $application = Invoke-AuthentikRequest -Method PATCH -Path "/core/applications/$slug/" -Body $body -Connection $connection
                $result.UpdatedApplications++
                Write-Verbose "Updated application $name"
            }
            else {
                $application = Invoke-AuthentikRequest -Method POST -Path '/core/applications/' -Body $body -Connection $connection
                $result.CreatedApplications++
                Write-Verbose "Created application $name"
            }

            $applications.Add([PSCustomObject]@{
                    Id           = [string]$application.pk
                    PbmUuid      = [string]$application.pbm_uuid
                    Key          = $row.Name
                    Name         = $name
                    Slug         = $slug
                    ProviderType = $providerType
                    ProviderId   = $providerPk
                    Hidden       = ($row.Hidden -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create application '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Applications = $applications.ToArray()

    Write-Verbose ("Applications: $($result.CreatedApplications) created, $($result.UpdatedApplications) updated, " +
        "$($result.ProvidersCreated) providers, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
