function New-AuthentikFlow {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded stages and flows from Data\AuthentikStages.csv and Data\AuthentikFlows.csv, and attaches the flows to seeded providers
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$FlowName,

        [Parameter()]
        [switch]$SkipProvider,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection
    $dataPath = Get-AuthentikDataPath

    $flowRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'AuthentikFlows.csv') -Encoding UTF8)
    $stageRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'AuthentikStages.csv') -Encoding UTF8)

    if ($FlowName) {
        $flowRows = @($flowRows | Where-Object { $FlowName -contains $_.Name })
        $unknown = @($FlowName | Where-Object { $flowRows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in AuthentikFlows.csv for: $($unknown -join ', ')" }
        $wantedStages = @($flowRows | ForEach-Object { $_.Stages -split ';' } | Where-Object { $_ } | Sort-Object -Unique)
        $stageRows = @($stageRows | Where-Object { $wantedStages -contains $_.Name })
    }

    # Each stage type has its own endpoint for create and update and one shared endpoint for
    # listing and deleting, the same shape as the policies.
    $stagePath = @{
        Identification        = 'identification'
        Password              = 'password'
        UserLogin             = 'user_login'
        Consent               = 'consent'
        AuthenticatorValidate = 'authenticator/validate'
        Deny                  = 'deny'
    }
    $stageTypeByModel = @{
        'authentik_stages_identification.identificationstage'          = 'Identification'
        'authentik_stages_password.passwordstage'                      = 'Password'
        'authentik_stages_user_login.userloginstage'                   = 'UserLogin'
        'authentik_stages_consent.consentstage'                        = 'Consent'
        'authentik_stages_authenticator_validate.authenticatorvalidatestage' = 'AuthenticatorValidate'
        'authentik_stages_deny.denystage'                              = 'Deny'
    }
    # The flow field a provider holds for each designation, and the endpoint each provider
    # type is edited at.
    $flowFieldByDesignation = @{ authentication = 'authentication_flow'; authorization = 'authorization_flow'; invalidation = 'invalidation_flow' }
    # Settings the API wants as a list even when the CSV holds one item, which the parser
    # would otherwise hand over as a string.
    $listSettings = @('backends', 'user_fields', 'device_classes', 'sources', 'configuration_stages', 'webauthn_allowed_device_types', 'webauthn_hints')
    # A proxy provider is validated whole on every update, so a partial PATCH that carries
    # only the flow is refused for the hosts it does not mention. These come back from a GET.
    $providerFieldsToResend = @{ proxy = @('external_host', 'internal_host', 'mode', 'internal_host_ssl_validation') }
    $providerPathByComponent = @{
        'ak-provider-oauth2-form' = 'oauth2'
        'ak-provider-proxy-form'  = 'proxy'
        'ak-provider-saml-form'   = 'saml'
        'ak-provider-ldap-form'   = 'ldap'
        'ak-provider-radius-form' = 'radius'
    }

    $result = [PSCustomObject]@{
        TotalFlows       = $flowRows.Count
        CreatedFlows     = 0
        UpdatedFlows     = 0
        StagesCreated    = 0
        StagesUpdated    = 0
        BindingsCreated  = 0
        ProvidersUpdated = 0
        Flows            = @()
        Errors           = @()
    }

    $existingStageByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Stages -Connection $connection)) {
        $existingStageByName[[string]$existing.name] = $existing
    }
    $existingFlowBySlug = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Flows -Connection $connection)) {
        $existingFlowBySlug[[string]$existing.slug] = $existing
    }
    $applicationBySlug = @{}
    if (-not $SkipProvider) {
        foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
            $applicationBySlug[[string]$application.slug] = $application
        }
    }

    # --- Stages ------------------------------------------------------------------------------
    $stagePkByKey = @{}
    foreach ($row in $stageRows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.DisplayName
        if (-not $stagePath.ContainsKey($row.Type)) {
            $message = "Stage '$name' has type '$($row.Type)', which the seed cannot create. Skipped."
            $result.Errors += $message
            Write-Warning $message
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, "Create Authentik $($row.Type) stage")) { continue }

        try {
            $body = @{ name = $name }
            $settings = ConvertFrom-AuthentikSetting -Text $row.Settings
            foreach ($key in $settings.Keys) {
                $value = $settings[$key]
                # Assigned as a variable, not from an if expression, because the pipeline
                # would unroll a one-element array back into the scalar the API refuses.
                if ($listSettings -contains $key) { $value = [object[]]@($value) }
                $body[$key] = $value
            }

            $stage = $null
            if ($existingStageByName.ContainsKey($name)) {
                $existing = $existingStageByName[$name]
                $existingType = $stageTypeByModel[[string]$existing.meta_model_name]
                if ($existingType -and $existingType -ne $row.Type) {
                    throw "A stage named '$name' already exists as a $existingType stage; the seed defines it as $($row.Type). Remove it first."
                }
                $stage = Invoke-AuthentikRequest -Method PATCH -Path "/stages/$($stagePath[$row.Type])/$($existing.pk)/" -Body $body -Connection $connection
                $result.StagesUpdated++
                Write-Verbose "Updated $($row.Type) stage $name"
            }
            else {
                $stage = Invoke-AuthentikRequest -Method POST -Path "/stages/$($stagePath[$row.Type])/" -Body $body -Connection $connection
                $result.StagesCreated++
                Write-Verbose "Created $($row.Type) stage $name"
            }
            $stagePkByKey[$row.Name] = [string]$stage.pk
        }
        catch {
            $message = "Failed to create stage '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    # --- Flows, their stage bindings, and the providers they are attached to ----------------
    $flows = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $flowRows) {
        $slug = '{0}-{1}' -f $marker.SlugPrefix, $row.Slug
        $name = '{0}{1}' -f $marker.Prefix, $row.Title

        if (-not $PSCmdlet.ShouldProcess("$name ($slug)", "Create Authentik $($row.Designation) flow")) { continue }

        try {
            $body = @{
                name               = $name
                slug               = $slug
                title              = $row.Title
                designation        = $row.Designation
                layout             = $(if ($row.Layout) { $row.Layout } else { 'stacked' })
                policy_engine_mode = 'any'
                denied_action      = 'message_continue'
            }

            $flow = $null
            if ($existingFlowBySlug.ContainsKey($slug)) {
                $flow = Invoke-AuthentikRequest -Method PATCH -Path "/flows/instances/$slug/" -Body $body -Connection $connection
                $result.UpdatedFlows++
                Write-Verbose "Updated flow $slug"
            }
            else {
                $flow = Invoke-AuthentikRequest -Method POST -Path '/flows/instances/' -Body $body -Connection $connection
                $result.CreatedFlows++
                Write-Verbose "Created flow $slug"
            }

            # Stage bindings, in the CSV's order, ten apart so one can be slotted in by hand. The
            # order comes from the CSV position, not from what was created, so a stage that
            # failed on one run and exists on the next lands where the CSV puts it, and an
            # existing binding that has drifted is moved rather than duplicated.
            $existingBindings = @(Invoke-AuthentikRequest -Method GET -Path '/flows/bindings/' `
                    -Query @{ target = [string]$flow.pk } -Connection $connection -Paginate)
            $boundStages = @()
            $stageKeys = @($row.Stages -split ';' | Where-Object { $_ })
            for ($index = 0; $index -lt $stageKeys.Count; $index++) {
                $stageKey = $stageKeys[$index]
                $order = $index * 10
                if (-not $stagePkByKey.ContainsKey($stageKey)) {
                    $message = "Flow '$slug' binds stage '$stageKey', which does not exist. Skipped."
                    $result.Errors += $message
                    Write-Warning $message
                    continue
                }
                $stagePk = $stagePkByKey[$stageKey]
                $existingBinding = @($existingBindings | Where-Object { [string]$_.stage -eq $stagePk })
                if ($existingBinding.Count -eq 0) {
                    $null = Invoke-AuthentikRequest -Method POST -Path '/flows/bindings/' -Connection $connection -Body @{
                        target = [string]$flow.pk
                        stage  = $stagePk
                        order  = $order
                    }
                    $result.BindingsCreated++
                }
                elseif ([int]$existingBinding[0].order -ne $order) {
                    $null = Invoke-AuthentikRequest -Method PATCH -Path "/flows/bindings/$($existingBinding[0].pk)/" `
                        -Body @{ order = $order } -Connection $connection
                }
                $boundStages += $stageKey
            }

            # Attach to the providers behind the named applications, at the field the flow's
            # designation dictates. Only a seeded application ever resolves here, so the seed
            # can only ever change a provider it created.
            $attached = @()
            if (-not $SkipProvider -and $flowFieldByDesignation.ContainsKey($row.Designation)) {
                $field = $flowFieldByDesignation[$row.Designation]
                foreach ($applicationKey in @($row.Applications -split ';' | Where-Object { $_ })) {
                    $applicationSlug = '{0}-{1}' -f $marker.SlugPrefix, $applicationKey
                    $application = $applicationBySlug[$applicationSlug]
                    $component = if ($application -and $application.provider_obj) { [string]$application.provider_obj.component } else { '' }
                    if (-not $application -or -not $application.provider -or -not $providerPathByComponent.ContainsKey($component)) {
                        $message = "Flow '$slug' names application '$applicationSlug', which does not exist or has no provider the seed can edit. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }
                    $providerType = $providerPathByComponent[$component]
                    $patch = @{ $field = [string]$flow.pk }
                    if ($providerFieldsToResend.ContainsKey($providerType)) {
                        $current = Invoke-AuthentikRequest -Method GET -Path "/providers/$providerType/$($application.provider)/" -Connection $connection
                        foreach ($resend in $providerFieldsToResend[$providerType]) {
                            if ($current.PSObject.Properties[$resend]) { $patch[$resend] = $current.$resend }
                        }
                    }
                    $null = Invoke-AuthentikRequest -Method PATCH -Path "/providers/$providerType/$($application.provider)/" `
                        -Body $patch -Connection $connection
                    $result.ProvidersUpdated++
                    $attached += $applicationSlug
                }
            }
            elseif (-not $SkipProvider -and $row.Applications) {
                $message = "Flow '$slug' is a $($row.Designation) flow, which no provider holds a field for. Not attached."
                $result.Errors += $message
                Write-Warning $message
            }

            $flows.Add([PSCustomObject]@{
                    Id           = [string]$flow.pk
                    Key          = $row.Name
                    Name         = $name
                    Slug         = $slug
                    Designation  = $row.Designation
                    Stages       = $boundStages
                    Applications = $attached
                })
        }
        catch {
            $message = "Failed to create flow '$slug': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Flows = $flows.ToArray()

    Write-Verbose ("Flows: $($result.CreatedFlows) created, $($result.UpdatedFlows) updated, " +
        "$($result.StagesCreated) stages created, $($result.BindingsCreated) bindings, " +
        "$($result.ProvidersUpdated) providers updated, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
