function New-PingOneResource {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded custom resources and the scopes on them
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

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneResources.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $existing = @{}
    foreach ($resource in (Invoke-PingOneRequest -Method GET -Path 'resources' -Paginate -Connection $connection)) {
        $existing[[string]$resource.name] = $resource
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $scopesCreated = 0

    foreach ($row in $rows) {
        $name = Resolve-PingOneSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $resource = $null

        if ($existing.ContainsKey($name)) {
            Write-Verbose "Resource $name already exists; reusing"
            $resource = $existing[$name]
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $resource.id })
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($name, 'Create PingOne resource')) { continue }

            # The audience takes the prefix too, because it is the value an access token names
            # and two environments seeded from the same data must not mint look-alike tokens.
            $body = @{
                name                       = $name
                description                = '{0} {1}' -f $row.Description, $marker.Tag
                audience                   = ('{0}{1}' -f $marker.Prefix, $row.Audience).ToLowerInvariant()
                accessTokenValiditySeconds = [int]$row.TokenSeconds
            }

            try {
                $resource = Invoke-PingOneRequest -Method POST -Path 'resources' -Body $body -Connection $connection
                $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $resource.id })
                Write-Verbose "Created resource $name"
            }
            catch {
                $errors.Add("Could not create resource ${name}: $($_.Exception.Message)")
                Write-Warning "Could not create resource ${name}: $($_.Exception.Message)"
                continue
            }
        }

        $existingScopes = @{}
        foreach ($scope in (Invoke-PingOneRequest -Method GET -Path "resources/$($resource.id)/scopes" -Paginate -Connection $connection)) {
            $existingScopes[[string]$scope.name] = $scope
        }

        foreach ($scopeName in @(($row.Scopes -split ';') | Where-Object { $_ })) {
            if ($existingScopes.ContainsKey($scopeName)) { continue }
            if (-not $PSCmdlet.ShouldProcess("$name/$scopeName", 'Create PingOne resource scope')) { continue }

            try {
                $null = Invoke-PingOneRequest -Method POST -Path "resources/$($resource.id)/scopes" `
                    -Body @{ name = $scopeName; description = $marker.Tag } -Connection $connection
                $scopesCreated++
            }
            catch {
                $errors.Add("Could not create scope $scopeName on ${name}: $($_.Exception.Message)")
            }
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalResources   = @($rows).Count
            CreatedResources = $created.Count
            ReusedResources  = $reused.Count
            ScopesCreated    = $scopesCreated
            Resources        = (@($created) + @($reused))
            Errors           = $errors.ToArray()
        }
    }
}
