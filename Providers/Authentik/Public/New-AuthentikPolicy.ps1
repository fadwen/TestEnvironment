function New-AuthentikPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Authentik policies from Data\AuthentikPolicies.csv and binds them to applications
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [switch]$SkipBinding,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikPolicies.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($PolicyName) {
        $rows = @($rows | Where-Object { $PolicyName -contains $_.Name })
        $unknown = @($PolicyName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    # Each policy type has its own endpoint for create and update, and one shared endpoint for
    # listing and deleting. The model name is what the shared listing reports, so an existing
    # policy can be updated at the endpoint its type owns.
    $typePath = @{
        Expression   = 'expression'
        Password     = 'password'
        Reputation   = 'reputation'
        GeoIP        = 'geoip'
        EventMatcher = 'event_matcher'
    }
    $typeByModel = @{
        'authentik_policies_expression.expressionpolicy'     = 'Expression'
        'authentik_policies_password.passwordpolicy'         = 'Password'
        'authentik_policies_reputation.reputationpolicy'     = 'Reputation'
        'authentik_policies_geoip.geoippolicy'               = 'GeoIP'
        'authentik_policies_event_matcher.eventmatcherpolicy' = 'EventMatcher'
    }

    $result = [PSCustomObject]@{
        TotalPolicies   = $rows.Count
        CreatedPolicies = 0
        UpdatedPolicies = 0
        BindingsCreated = 0
        Policies        = @()
        Errors          = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Policies -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    $targetBySlug = @{}
    if (-not $SkipBinding) {
        foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
            $targetBySlug[[string]$application.slug] = [string]$application.pbm_uuid
        }
    }

    $policies = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name
        $type = if ($row.Type) { $row.Type } else { 'Expression' }

        if (-not $typePath.ContainsKey($type)) {
            $message = "Policy '$name' has type '$type', which the seed cannot create. Skipped."
            $result.Errors += $message
            Write-Warning $message
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, "Create Authentik $type policy")) { continue }

        try {
            $body = @{ name = $name; execution_logging = $false }
            if ($type -eq 'Expression') {
                $body.expression = $row.Expression.Replace('{prefix}', $marker.Prefix).Replace('`n', "`n")
            }
            $settings = ConvertFrom-AuthentikSetting -Text $row.Settings
            foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }

            $policy = $null
            if ($existingByName.ContainsKey($name)) {
                $existing = $existingByName[$name]
                $existingType = $typeByModel[[string]$existing.meta_model_name]
                if ($existingType -and $existingType -ne $type) {
                    throw "A policy named '$name' already exists as a $existingType policy; the seed defines it as $type. Remove it first."
                }
                $policy = Invoke-AuthentikRequest -Method PATCH -Path "/policies/$($typePath[$type])/$($existing.pk)/" -Body $body -Connection $connection
                $result.UpdatedPolicies++
                Write-Verbose "Updated $type policy $name"
            }
            else {
                $policy = Invoke-AuthentikRequest -Method POST -Path "/policies/$($typePath[$type])/" -Body $body -Connection $connection
                $result.CreatedPolicies++
                Write-Verbose "Created $type policy $name"
            }

            $boundTo = $null
            $bound = $false
            if (-not $SkipBinding -and $row.Target) {
                $targetSlug = '{0}-{1}' -f $marker.SlugPrefix, $row.Target
                if (-not $targetBySlug.ContainsKey($targetSlug)) {
                    $message = "Policy '$name' targets application '$targetSlug', which does not exist. Created unbound."
                    $result.Errors += $message
                    Write-Warning $message
                }
                else {
                    $target = $targetBySlug[$targetSlug]
                    $existingBindings = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                            -Query @{ policy = [string]$policy.pk; target = $target } -Connection $connection -Paginate)
                    if ($existingBindings.Count -eq 0) {
                        $null = Invoke-AuthentikRequest -Method POST -Path '/policies/bindings/' -Connection $connection -Body @{
                            policy  = [string]$policy.pk
                            target  = $target
                            order   = [int]$row.Order
                            enabled = ($row.Enabled -eq 'TRUE')
                            negate  = ($row.Negate -eq 'TRUE')
                        }
                        $result.BindingsCreated++
                    }
                    $boundTo = $targetSlug
                    $bound = $true
                }
            }

            $policies.Add([PSCustomObject]@{
                    Id      = [string]$policy.pk
                    Key     = $row.Name
                    Name    = $name
                    Type    = $type
                    Target  = $boundTo
                    Bound   = $bound
                    Order   = $(if ($row.Order -match '^\d+$') { [int]$row.Order } else { $null })
                    Enabled = ($row.Enabled -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create policy '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Policies = $policies.ToArray()

    Write-Verbose ("Policies: $($result.CreatedPolicies) created, $($result.UpdatedPolicies) updated, " +
        "$($result.BindingsCreated) bindings, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
