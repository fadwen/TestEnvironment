function New-PingOneApplication {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded applications across every protocol and grants them their resource scopes
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection
    $marker = Get-PingOneSeedMarker -Prefix $connection.Prefix
    $dataPath = Get-PingOneDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'PingOneApplications.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    # Groups and resources, by the name the seed gave them.
    $groupNameByKey = @{}
    foreach ($groupRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'PingOneGroups.csv') -Encoding UTF8)) {
        $groupNameByKey[$groupRow.Key] = Resolve-PingOneSeedName -Key $groupRow.Name -Kind DisplayName -Connection $connection
    }
    $groupByName = @{}
    foreach ($group in (Invoke-PingOneRequest -Method GET -Path 'groups' -Paginate -Connection $connection)) {
        $groupByName[[string]$group.name] = $group
    }

    $resourceNameByKey = @{}
    foreach ($resourceRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'PingOneResources.csv') -Encoding UTF8)) {
        $resourceNameByKey[$resourceRow.Key] = Resolve-PingOneSeedName -Key $resourceRow.Name -Kind DisplayName -Connection $connection
    }
    $resourceByName = @{}
    foreach ($resource in (Invoke-PingOneRequest -Method GET -Path 'resources' -Paginate -Connection $connection)) {
        $resourceByName[[string]$resource.name] = $resource
    }

    $existing = @{}
    foreach ($application in (Invoke-PingOneRequest -Method GET -Path 'applications' -Paginate -Connection $connection)) {
        $existing[[string]$application.name] = $application
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $grantsApplied = 0

    $split = { param($value) @(([string]$value -split ';') | Where-Object { $_ }) }
    $expand = { param($value) ([string]$value).Replace('{domain}', $connection.EmailDomain) }

    foreach ($row in $rows) {
        $name = Resolve-PingOneSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $application = $null

        if ($existing.ContainsKey($name)) {
            Write-Verbose "Application $name already exists; reusing"
            $application = $existing[$name]
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $application.id })
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($name, 'Create PingOne application')) { continue }

            $body = @{
                name        = $name
                description = '{0} {1}' -f $row.Purpose, $marker.Tag
                enabled     = [bool]::Parse($row.Enabled)
                type        = $row.Type
                protocol    = $row.Protocol
            }

            if ($row.Protocol -eq 'SAML') {
                $body['spEntityId'] = & $expand $row.SpEntityId
                $body['acsUrls'] = @(& $split (& $expand $row.AcsUrls))
                $body['assertionDuration'] = 3600
            }
            else {
                $body['grantTypes'] = @(& $split $row.GrantTypes)
                $body['responseTypes'] = @(& $split $row.ResponseTypes)
                $body['tokenEndpointAuthMethod'] = $row.TokenAuth
                $body['redirectUris'] = @(& $split (& $expand $row.RedirectUris))

                # A public client runs safely only with PKCE, so it is never seeded without it.
                if ($row.TokenAuth -eq 'NONE') { $body['pkceEnforcement'] = 'S256_REQUIRED' }
            }

            $assignedGroupIds = foreach ($groupKey in (& $split $row.AssignGroups)) {
                $groupName = $groupNameByKey[$groupKey]
                if ($groupName -and $groupByName.ContainsKey($groupName)) {
                    @{ id = $groupByName[$groupName].id }
                }
                else {
                    $errors.Add("Group '$groupKey' for application $name does not exist; run New-PingOneGroup first")
                }
            }
            if (@($assignedGroupIds).Count -gt 0) {
                $body['accessControl'] = @{ group = @{ type = 'ANY_GROUP'; groups = @($assignedGroupIds) } }
            }

            try {
                $application = Invoke-PingOneRequest -Method POST -Path 'applications' -Body $body -Connection $connection
                $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $application.id; Protocol = $row.Protocol })
                Write-Verbose "Created application $name"
            }
            catch {
                $errors.Add("Could not create application ${name}: $($_.Exception.Message)")
                Write-Warning "Could not create application ${name}: $($_.Exception.Message)"
                continue
            }
        }

        # Grants, one per resource. SAML applications are granted nothing, because they are
        # not issued access tokens.
        if ($row.Protocol -eq 'SAML') { continue }

        $scopesByResource = @{}
        foreach ($entry in (& $split $row.Scopes)) {
            $resourceKey, $scopeName = $entry -split ':', 2
            if (-not $scopesByResource.ContainsKey($resourceKey)) { $scopesByResource[$resourceKey] = @() }
            $scopesByResource[$resourceKey] += $scopeName
        }
        if ($scopesByResource.Count -eq 0) { continue }

        $existingGrants = @(Invoke-PingOneRequest -Method GET -Path "applications/$($application.id)/grants" -Paginate -Connection $connection)

        foreach ($resourceKey in $scopesByResource.Keys) {
            $resourceName = $resourceNameByKey[$resourceKey]
            $resource = $null
            if ($resourceName) { $resource = $resourceByName[$resourceName] }
            if (-not $resource) {
                $errors.Add("Resource '$resourceKey' for application $name does not exist; run New-PingOneResource first")
                continue
            }

            if (@($existingGrants | Where-Object { $_.resource.id -eq $resource.id })) { continue }

            $scopeObjects = @(Invoke-PingOneRequest -Method GET -Path "resources/$($resource.id)/scopes" -Paginate -Connection $connection)
            $wanted = foreach ($scopeName in $scopesByResource[$resourceKey]) {
                $match = @($scopeObjects | Where-Object { $_.name -eq $scopeName })
                if ($match) { @{ id = $match[0].id } }
                else { $errors.Add("Scope '$scopeName' on $resourceName does not exist for application $name") }
            }
            if (@($wanted).Count -eq 0) { continue }

            if (-not $PSCmdlet.ShouldProcess("$name -> $resourceName", 'Grant PingOne resource scopes')) { continue }

            try {
                $null = Invoke-PingOneRequest -Method POST -Path "applications/$($application.id)/grants" `
                    -Body @{ resource = @{ id = $resource.id }; scopes = @($wanted) } -Connection $connection
                $grantsApplied++
            }
            catch {
                $errors.Add("Could not grant $resourceName to ${name}: $($_.Exception.Message)")
            }
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalApplications   = @($rows).Count
            CreatedApplications = $created.Count
            ReusedApplications  = $reused.Count
            GrantsApplied       = $grantsApplied
            Applications        = (@($created) + @($reused))
            Errors              = $errors.ToArray()
        }
    }
}
