function New-FreeIPAService {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Kerberos services and delegation rules from Data\FreeIPAServices.csv and Data\FreeIPAServiceDelegation.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Principal,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $dataPath = Get-FreeIPADataPath

    $servicePath = Join-Path -Path $dataPath -ChildPath 'FreeIPAServices.csv'
    $serviceRows = @(Import-Csv -Path $servicePath -Encoding UTF8)
    $delegationRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'FreeIPAServiceDelegation.csv') -Encoding UTF8)
    if ($Principal) {
        $serviceRows = @($serviceRows | Where-Object { $Principal -contains $_.Principal })
        $unknown = @($Principal | Where-Object { $serviceRows.Principal -notcontains $_ })
        if ($unknown) { throw "No definition in $servicePath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalServices            = $serviceRows.Count
        CreatedServices          = 0
        UpdatedServices          = 0
        DelegationRulesCreated   = 0
        DelegationTargetsCreated = 0
        MembershipsApplied       = 0
        Services                 = @()
        Errors                   = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $record = { param($problem) $result.Errors += $problem; Write-Error $problem }

    # 'HTTP/web01' -> 'HTTP/zz-test-web01.ipa.example.com', and with the realm for membership.
    $principalOf = {
        param($key)
        $type, $hostKey = $key -split '/', 2
        '{0}/{1}' -f $type, (Resolve-FreeIPASeedName -Key $hostKey -Kind Host -Marker $marker -Connection $connection)
    }
    $qualified = { param($name) if ($connection.Realm) { '{0}@{1}' -f $name, $connection.Realm } else { $name } }

    $existingServices = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type Services -Connection $connection)) {
        $name = [string](@($entry.krbcanonicalname)[0])
        $existingServices[($name -split '@')[0]] = $entry
    }
    $existingTargets = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type ServiceDelegationTargets -Connection $connection)) { $existingTargets[[string](@($entry.cn)[0])] = $entry }
    $existingRules = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type ServiceDelegationRules -Connection $connection)) { $existingRules[[string](@($entry.cn)[0])] = $entry }

    # --- Services -------------------------------------------------------------------------------
    $services = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $serviceRows) {
        $name = & $principalOf $row.Principal
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA service')) { continue }
        try {
            $options = @{}
            if ($row.AuthIndicators) { $options['krbprincipalauthind'] = [object[]]@(& $split $row.AuthIndicators) }

            if ($existingServices.ContainsKey($name)) {
                if ($options.Count -gt 0) {
                    $null = Invoke-FreeIPARequest -Method 'service_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                }
                $result.UpdatedServices++
            }
            else {
                # Force, because the host is a record with no DNS entry.
                $options['force'] = $true
                $null = Invoke-FreeIPARequest -Method 'service_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedServices++
                Write-Verbose "Created service $name"
            }

            if ($row.ManagedBy) {
                $managers = @(& $split $row.ManagedBy | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Kind Host -Marker $marker -Connection $connection })
                $outcome = Add-FreeIPAMember -Method 'service_add_host' -Name $name -Members @{ host = $managers } -Connection $connection
                $result.MembershipsApplied += $outcome.Completed
                foreach ($problem in $outcome.Errors) { & $record $problem }
            }

            $services.Add([PSCustomObject]@{ Key = $row.Principal; Principal = $name })
        }
        catch { & $record "Failed to create service '$name': $($_.Exception.Message)" }
    }

    # --- Delegation: targets first, then the rules that name them -----------------------------
    foreach ($row in ($delegationRows | Where-Object Kind -eq 'Target')) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA service delegation target')) { continue }
        try {
            if (-not $existingTargets.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'servicedelegationtarget_add' -Arguments $name -Connection $connection
                $result.DelegationTargetsCreated++
            }
            $members = @(& $split $row.Members | ForEach-Object { & $qualified (& $principalOf $_) })
            $outcome = Add-FreeIPAMember -Method 'servicedelegationtarget_add_member' -Name $name -Members @{ principal = $members } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }
        }
        catch { & $record "Failed to create delegation target '$name': $($_.Exception.Message)" }
    }

    foreach ($row in ($delegationRows | Where-Object Kind -eq 'Rule')) {
        $name = Resolve-FreeIPASeedName -Key $row.Name -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA service delegation rule')) { continue }
        try {
            if (-not $existingRules.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'servicedelegationrule_add' -Arguments $name -Connection $connection
                $result.DelegationRulesCreated++
            }
            $members = @(& $split $row.Members | ForEach-Object { & $qualified (& $principalOf $_) })
            $outcome = Add-FreeIPAMember -Method 'servicedelegationrule_add_member' -Name $name -Members @{ principal = $members } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }

            $targets = @(& $split $row.Targets | ForEach-Object { Resolve-FreeIPASeedName -Key $_ -Marker $marker -Connection $connection })
            $outcome = Add-FreeIPAMember -Method 'servicedelegationrule_add_target' -Name $name -Members @{ servicedelegationtarget = $targets } -Connection $connection
            $result.MembershipsApplied += $outcome.Completed
            foreach ($problem in $outcome.Errors) { & $record $problem }
        }
        catch { & $record "Failed to create delegation rule '$name': $($_.Exception.Message)" }
    }

    $result.Services = $services.ToArray()
    Write-Verbose "Services: $($result.CreatedServices) created, $($result.UpdatedServices) updated, $($result.DelegationTargetsCreated) targets, $($result.DelegationRulesCreated) rules, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
