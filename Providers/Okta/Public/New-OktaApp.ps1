function New-OktaApp {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded app integrations and assigns groups and users to them
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$AppName,

        [Parameter()]
        [switch]$SkipAssignment,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $dataPath = Get-OktaDataPath
    $rows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaApps.csv') -Encoding UTF8)
    $groupRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaGroups.csv') -Encoding UTF8)

    if ($AppName) {
        $rows = @($rows | Where-Object { $AppName -contains $_.Name })
        $unknown = @($AppName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No app definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalApps      = $rows.Count
        CreatedApps    = 0
        ExistingApps   = 0
        GroupsAssigned = 0
        UsersAssigned  = 0
        Apps           = @()
        Errors         = @()
    }

    # Resolve both directories once. At this scale the whole mapping costs two calls, and doing
    # it per assignment would cost dozens.
    $groupIdByKey = @{}
    $userIdByLogin = @{}
    if (-not $SkipAssignment) {
        $oktaNameByKey = @{}
        foreach ($groupRow in $groupRows) {
            $oktaNameByKey[$groupRow.Name] = '{0}-{1}' -f $connection.Prefix, $groupRow.DisplayName
        }

        $seededGroups = @(Get-OktaSeededGroup -Prefix $connection.Prefix `
            -SeedMarker $connection.SeedMarker)
        foreach ($group in $seededGroups) {
            $key = @($oktaNameByKey.Keys | Where-Object { $oktaNameByKey[$_] -eq $group.profile.name })
            if ($key.Count -eq 1) { $groupIdByKey[$key[0]] = $group.id }
        }

        $seeded = @(Get-OktaSeededUser -Prefix $connection.Prefix `
            -EmailDomain $connection.EmailDomain)
        foreach ($user in $seeded) { $userIdByLogin[$user.profile.login] = $user.id }
    }

    $apps = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $label = '{0}-{1}' -f $connection.Prefix, $row.Label

        if (-not $PSCmdlet.ShouldProcess($label, "Create Okta app ($($row.SignOnMode))")) { continue }

        try {
            $existing = @(Invoke-OktaRequest -Method GET -Path '/api/v1/apps' `
                -Query @{ q = $label; limit = 50 } -Paginate |
                Where-Object { $_.label -eq $label })

            if ($existing.Count -gt 0) {
                # Reused rather than updated. An app's settings are bound up with its sign-on
                # mode and, for OIDC, with a client secret already issued; rewriting them on a
                # re-run would rotate credentials nobody asked to rotate. Assignments below are
                # reapplied either way, which is the part that actually matters.
                $app = $existing[0]
                $result.ExistingApps++
                Write-Verbose "Reusing existing app $label"
            }
            else {
                # The CSV URLs carry the module's default domain. Rewriting them to the
                # connection's domain is what keeps the teardown marker working under a custom
                # -EmailDomain, since the URL is the only marker every app type preserves.
                $url = $row.Url -replace [regex]::Escape($script:DefaultSeedDomain),
                    $connection.EmailDomain

                $body = [ordered]@{
                    name       = $row.Template
                    label      = $label
                    signOnMode = $row.SignOnMode
                    # Okta accepts this and then silently discards it for every sign-on mode
                    # except OPENID_CONNECT - verified against a live tenant, and a follow-up
                    # PUT does not help. It is still sent because it IS honoured for OIDC apps,
                    # but Get-OktaSeededApp cannot rely on it and falls back to the URL.
                    profile    = @{ labSeedTag = $connection.SeedTag; labCategory = $row.Category }
                }

                switch ($row.Template) {
                    'bookmark' {
                        $body.settings = @{ app = @{ url = $url; requestIntegration = $false } }
                    }
                    'template_swa' {
                        $body.settings = @{ app = @{
                            url           = $url
                            usernameField = '#txtbox-username'
                            passwordField = '#txtbox-password'
                            buttonField   = 'btn-login'
                        } }
                    }
                    'oidc_client' {
                        $body.credentials = @{
                            oauthClient = @{ token_endpoint_auth_method = 'client_secret_basic' }
                        }
                        $logoutUri = '{0}://{1}/' -f ([uri]$url).Scheme, ([uri]$url).Host
                        $body.settings = @{ oauthClient = @{
                            application_type          = 'web'
                            grant_types               = @('authorization_code')
                            response_types            = @('code')
                            redirect_uris             = @($url)
                            post_logout_redirect_uris = @($logoutUri)
                        } }
                    }
                    default { throw "Unknown app template '$($row.Template)'." }
                }

                $app = Invoke-OktaRequest -Method POST -Path '/api/v1/apps' -Body $body
                $result.CreatedApps++
                Write-Verbose "Created app $label"
            }

            $assignedGroups = @()
            $assignedUsers = @()

            if (-not $SkipAssignment) {
                foreach ($groupKey in @($row.Groups -split ';' | Where-Object { $_ })) {
                    if (-not $groupIdByKey.ContainsKey($groupKey)) {
                        $message = "App '$label' lists group '$groupKey', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # PUT is idempotent: reassigning an already-assigned group is a no-op rather
                    # than an error, so a re-run needs no membership check.
                    $null = Invoke-OktaRequest -Method PUT `
                        -Path "/api/v1/apps/$($app.id)/groups/$($groupIdByKey[$groupKey])"
                    $assignedGroups += $groupKey
                    $result.GroupsAssigned++
                }

                # POST is NOT idempotent here, so existing assignees are read first. Without
                # this, a re-run reports a conflict for every user already assigned.
                $alreadyAssigned = @()
                if ($result.ExistingApps -gt 0 -or $existing.Count -gt 0) {
                    $alreadyAssigned = @(Invoke-OktaRequest -Method GET `
                        -Path "/api/v1/apps/$($app.id)/users" -Paginate |
                        ForEach-Object { $_.id })
                }

                foreach ($loginPrefix in @($row.DirectUsers -split ';' | Where-Object { $_ })) {
                    $login = '{0}@{1}' -f $loginPrefix, $connection.EmailDomain

                    if (-not $userIdByLogin.ContainsKey($login)) {
                        $message = "App '$label' lists user '$login', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    $userId = $userIdByLogin[$login]
                    if ($alreadyAssigned -contains $userId) {
                        Write-Verbose "$login is already assigned to $label"
                        continue
                    }

                    $null = Invoke-OktaRequest -Method POST -Path "/api/v1/apps/$($app.id)/users" `
                        -Body @{ id = $userId; scope = 'USER' }
                    $assignedUsers += $login
                    $result.UsersAssigned++
                }
            }

            $apps.Add([PSCustomObject]@{
                Id         = $app.id
                Key        = $row.Name
                Label      = $label
                SignOnMode = $row.SignOnMode
                Category   = $row.Category
                Groups     = $assignedGroups
                DirectUsers = $assignedUsers
            })
        }
        catch {
            $message = "Failed to create app '$label': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Apps = $apps.ToArray()

    Write-Verbose ("Apps: $($result.CreatedApps) created, $($result.ExistingApps) reused, " +
        "$($result.GroupsAssigned) group assignments, $($result.UsersAssigned) direct assignments")

    if ($PassThru) { return $result }
}
