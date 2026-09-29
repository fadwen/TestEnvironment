function New-OneLoginApp {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded OIDC and SAML apps and grants them to their roles
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$SaveAppSecret,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    # Passed only when given: -Tier $null fails the ValidateSet, which is how a seed with no -Tier
    # once skipped every one of these steps.
    $scope = if ($Tier) { Get-OneLoginSeedScope -Tier $Tier } else { Get-OneLoginSeedScope }
    $dataPath = Get-OneLoginDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginApps.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $roleNameByKey = @{}
    foreach ($roleRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginRoles.csv') -Encoding UTF8)) {
        $roleNameByKey[$roleRow.Key] = Resolve-OneLoginSeedName -Key $roleRow.Name -Kind DisplayName -Connection $connection
    }
    # Only a role the seed may use: its own, or an empty one of its names. An app is never granted
    # to a role that holds anybody else, because that would give them the app.
    $roleByName = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -Connection $connection)) { $roleByName[[string]$role.name] = $role }

    $existing = @{}
    foreach ($app in @(Invoke-OneLoginRequest -Method GET -Path 'apps' -Paginate -Connection $connection)) {
        if ($null -ne $app -and $app.name) { $existing[[string]$app.name] = $app }
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $grantsByRoleId = @{}
    $secretsSaved = 0
    $secretsUnavailable = [System.Collections.Generic.List[string]]::new()
    # Only a confidential client has a secret worth keeping. A public or native client
    # authenticates with none, and a SAML app has no client at all.
    $takesSecret = { param($row) $row.Connector -eq 'OIDC' -and @('Basic', 'Post') -contains $row.TokenAuth }
    $savedAppIds = @{}
    if ($SaveAppSecret) {
        foreach ($record in @(Get-OneLoginAppSecretRecord -Subdomain $connection.Subdomain)) { $savedAppIds[$record.AppId] = $true }
    }

    $split = { param($value) @(([string]$value -split ';') | Where-Object { $_ }) }
    $expand = { param($value) ([string]$value).Replace('{domain}', $connection.EmailDomain) }

    foreach ($row in $rows) {
        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $appId = $null

        if ($existing.ContainsKey($name)) {
            $app = $existing[$name]
            if (-not ([string]$app.description).Contains($marker.Tag)) {
                $errors.Add("App '$name' already exists without the seed tag in its description. It is somebody else's; it is left alone and granted to nothing.")
                continue
            }
            Write-Verbose "App $name already exists; reusing it"
            $appId = $app.id
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $appId; Connector = $row.Connector })
            if ($SaveAppSecret -and (& $takesSecret $row) -and -not $savedAppIds.ContainsKey([string]$appId)) {
                # OneLogin shows a secret once, in the answer to the create. An app that already
                # existed cannot have its secret saved now; saying so beats a record that is missing.
                $secretsUnavailable.Add($row.Key)
                Write-Warning "The client secret of $name was not saved: OneLogin shows it only when the app is created, and this app already existed. Remove it and seed again, or regenerate its secret in the portal."
            }
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin app')) { continue }

            # The tag inside Core's sentence, so an administrator who finds this app in a
            # production portal is told what made it and that it is safe to delete.
            $body = @{
                connector_id = $script:OneLoginConnector[$row.Connector]
                name         = $name
                description  = '{0}. {1}' -f $row.Description, $marker.Description
                visible      = [bool]::Parse($row.Visible)
            }
            if ($row.Connector -eq 'SAML') {
                $consumer = & $expand $row.ConsumerUrl
                $body['configuration'] = @{
                    audience            = & $expand $row.Audience
                    consumer_url        = $consumer
                    recipient           = $consumer
                    validator           = '^{0}$' -f [regex]::Escape($consumer)
                    login               = & $expand $row.LoginUrl
                    signature_algorithm = 'SHA-256'
                }
            }
            else {
                $configuration = @{
                    redirect_uri               = & $expand $row.RedirectUri
                    oidc_application_type      = $(if ($row.AppType -eq 'Native') { 1 } else { 0 })
                    token_endpoint_auth_method = $script:OneLoginTokenAuth[$row.TokenAuth]
                }
                if ($row.LoginUrl) { $configuration['login_url'] = & $expand $row.LoginUrl }
                $body['configuration'] = $configuration
            }

            try {
                # The response carries the new client secret, and no later read of the app does.
                # Unless -SaveAppSecret asks for it to be kept, protected, it is dropped here.
                $response = Invoke-OneLoginRequest -Method POST -Path 'apps' -Body $body -Connection $connection
                $appId = $response.id
                $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $appId; Connector = $row.Connector })
                Write-Verbose "Created app $name"
                if ($SaveAppSecret -and (& $takesSecret $row)) {
                    $sso = $response.sso
                    if ($sso -and $sso.client_id -and $sso.client_secret) {
                        try {
                            $null = Export-OneLoginAppSecret -Subdomain $connection.Subdomain -AppId ([string]$appId) -AppKey $row.Key -AppName $name `
                                -ClientId ([string]$sso.client_id) -ClientSecret ([string]$sso.client_secret) `
                                -UseSecretStore:$UseSecretStore -VaultPassword $VaultPassword -Confirm:$false
                            $secretsSaved++
                        }
                        catch { $errors.Add("App $name was created, but its client secret could not be saved: $($_.Exception.Message)") }
                    }
                    else {
                        $errors.Add("App $name was created, but OneLogin's answer carried no client secret to save.")
                    }
                    $sso = $null
                }
                $response = $null
            }
            catch {
                $hint = ''
                if ($_.Exception.Message -match 'limit') { $hint = ' The account''s plan allows no more apps; a OneLogin trial allows five.' }
                $errors.Add("Could not create app ${name}: $($_.Exception.Message)$hint")
                Write-Warning "Could not create app ${name}: $($_.Exception.Message)$hint"
                continue
            }
        }

        foreach ($roleKey in (& $split $row.Roles)) {
            if (-not $scope.Roles.Contains($roleKey)) { continue }
            $role = $roleByName[$roleNameByKey[$roleKey]]
            if (-not $role) {
                $errors.Add("Role '$roleKey' for app $name does not exist, or is not one the seed may use; run New-OneLoginRole first")
                continue
            }
            if (-not $grantsByRoleId.ContainsKey([string]$role.id)) {
                $grantsByRoleId[[string]$role.id] = [PSCustomObject]@{ Role = $role; AppIds = New-Object System.Collections.Generic.List[string] }
            }
            $grantsByRoleId[[string]$role.id].AppIds.Add([string]$appId)
        }
    }

    # One request per role. The endpoint sets a role's apps, so what the role already holds is
    # read and kept rather than trusted to survive.
    $grantsApplied = 0
    foreach ($grant in $grantsByRoleId.Values) {
        $current = @(Invoke-OneLoginRequest -Method GET -Path "roles/$($grant.Role.id)/apps" -Paginate -Connection $connection |
                Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })
        $missing = @($grant.AppIds | Where-Object { $current -notcontains $_ } | Sort-Object -Unique)
        if ($missing.Count -eq 0) { continue }

        if (-not $PSCmdlet.ShouldProcess("$($grant.Role.name) <- $($missing.Count) app(s)", 'Grant OneLogin apps to role')) { continue }

        # Written as JSON here rather than handed over as an array: piped to ConvertTo-Json, a
        # one-element array becomes the bare number, and the endpoint wants a list.
        $all = @(@($current) + @($missing) | Sort-Object -Unique)
        $json = '[{0}]' -f ($all -join ',')
        try {
            $null = Invoke-OneLoginRequest -Method PUT -Path "roles/$($grant.Role.id)/apps" -Body $json -Connection $connection
            $grantsApplied += $missing.Count
        }
        catch {
            $errors.Add("Could not grant apps to role $($grant.Role.name): $($_.Exception.Message)")
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalApps          = @($rows).Count
            CreatedApps        = $created.Count
            ReusedApps         = $reused.Count
            GrantsApplied      = $grantsApplied
            SecretsSaved       = $secretsSaved
            SecretsUnavailable = $secretsUnavailable.ToArray()
            Apps               = (@($created) + @($reused))
            Errors             = $errors.ToArray()
        }
    }
}
