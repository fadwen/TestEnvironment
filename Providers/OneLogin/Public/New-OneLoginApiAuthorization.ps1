function New-OneLoginApiAuthorization {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded API authorization servers with their scopes and claims, and lets seeded apps ask for them
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    $dataPath = Get-OneLoginDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginApiAuthorizations.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    # Client links go to proved seeded apps only: linking somebody else's app would let it ask for a
    # seeded API's tokens, and let a seeded API issue tokens to it.
    $appNameByKey = @{}
    foreach ($appRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginApps.csv') -Encoding UTF8)) {
        $appNameByKey[$appRow.Key] = Resolve-OneLoginSeedName -Key $appRow.Name -Kind DisplayName -Connection $connection
    }
    $appByName = @{}
    foreach ($app in @(Get-OneLoginSeededObject -Type Apps -Connection $connection)) { $appByName[[string]$app.name] = $app }

    $existing = @{}
    foreach ($server in @(Invoke-OneLoginRequest -Method GET -Path 'api_authorizations' -Paginate -Connection $connection)) {
        if ($null -ne $server -and $server.name) { $existing[[string]$server.name] = $server }
    }

    $split = { param($value) @(([string]$value -split '\|') | Where-Object { $_ }) }
    $list = { param([string]$Path) @(Invoke-OneLoginRequest -Method GET -Path $Path -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ }) }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $scopesAdded = 0
    $claimsAdded = 0
    $clientsLinked = 0

    foreach ($row in $rows) {
        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection
        $identifier = 'https://api.{0}/{1}' -f $connection.EmailDomain, ([string]$row.Path).TrimStart('/')
        $server = $null

        if ($existing.ContainsKey($name)) {
            $server = $existing[$name]
            if (-not ([string]$server.description).Contains($marker.Tag)) {
                $errors.Add("API authorization '$name' already exists without the seed tag in its description. It is somebody else's; it is left alone.")
                continue
            }
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $server.id })
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin API authorization server')) { continue }
            $body = @{
                name          = $name
                description   = '{0}. {1}' -f $row.Description, $marker.Description
                configuration = @{
                    resource_identifier             = $identifier
                    audiences                       = @($identifier)
                    access_token_expiration_minutes = [int]$row.TokenMinutes
                }
            }
            try {
                $server = Invoke-OneLoginRequest -Method POST -Path 'api_authorizations' -Body $body -Connection $connection
                $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $server.id })
                Write-Verbose "Created API authorization $name"
            }
            catch {
                $errors.Add("Could not create API authorization ${name}: $($_.Exception.Message)")
                Write-Warning "Could not create API authorization ${name}: $($_.Exception.Message)"
                continue
            }
        }

        # Scopes, by value.
        $scopeByValue = @{}
        foreach ($scope in (& $list "api_authorizations/$($server.id)/scopes")) { $scopeByValue[[string]$scope.value] = $scope }
        foreach ($entry in (& $split $row.Scopes)) {
            $value, $description = $entry -split '=', 2
            if ($scopeByValue.ContainsKey($value)) { continue }
            if (-not $PSCmdlet.ShouldProcess("$name : $value", 'Create OneLogin API scope')) { continue }
            try {
                $scope = Invoke-OneLoginRequest -Method POST -Path "api_authorizations/$($server.id)/scopes" -Body @{ value = $value; description = $description } -Connection $connection
                $scopeByValue[$value] = [PSCustomObject]@{ id = $scope.id; value = $value }
                $scopesAdded++
            }
            catch { $errors.Add("Could not create scope $value on ${name}: $($_.Exception.Message)") }
        }

        # Claims, by name.
        $claimNames = @((& $list "api_authorizations/$($server.id)/claims") | ForEach-Object { [string]$_.name })
        foreach ($entry in (& $split $row.Claims)) {
            $claim, $source = $entry -split '=', 2
            if ($claimNames -contains $claim) { continue }
            if (-not $PSCmdlet.ShouldProcess("$name : $claim", 'Create OneLogin API claim')) { continue }
            try {
                $null = Invoke-OneLoginRequest -Method POST -Path "api_authorizations/$($server.id)/claims" -Body @{ name = $claim; user_attribute_mappings = $source } -Connection $connection
                $claimsAdded++
            }
            catch { $errors.Add("Could not create claim $claim on ${name}: $($_.Exception.Message)") }
        }

        # Clients: seeded apps, each with the scopes the data grants it.
        $linked = @{}
        foreach ($client in (& $list "api_authorizations/$($server.id)/clients")) { $linked[[string]$client.app_id] = @($client.scopes | ForEach-Object { [string]$_.value }) }
        foreach ($entry in (& $split $row.Clients)) {
            $appKey, $scopeList = $entry -split '=', 2
            $app = $appByName[$appNameByKey[$appKey]]
            if (-not $app) {
                $errors.Add("App '$appKey' for API authorization $name does not exist, or is not seeded; run New-OneLoginApp first")
                continue
            }
            $wanted = @(([string]$scopeList -split ' ') | Where-Object { $_ })
            $scopeIds = @($wanted | ForEach-Object { if ($scopeByValue.ContainsKey($_)) { [long]$scopeByValue[$_].id } })
            if ($scopeIds.Count -ne $wanted.Count) {
                $errors.Add("App '$appKey' is granted a scope that API authorization $name does not have")
                continue
            }
            $have = if ($linked.ContainsKey([string]$app.id)) { @($linked[[string]$app.id]) } else { $null }
            if ($null -ne $have -and @($wanted | Where-Object { $have -notcontains $_ }).Count -eq 0) { continue }
            if (-not $PSCmdlet.ShouldProcess("$name <- $($app.name)", 'Let a OneLogin app ask for an API')) { continue }
            try {
                if ($null -eq $have) {
                    $null = Invoke-OneLoginRequest -Method POST -Path "api_authorizations/$($server.id)/clients" -Body @{ app_id = [long]$app.id; scopes = $scopeIds } -Connection $connection
                }
                else {
                    $null = Invoke-OneLoginRequest -Method PUT -Path "api_authorizations/$($server.id)/clients/$($app.id)" -Body @{ scopes = $scopeIds } -Connection $connection
                }
                $clientsLinked++
            }
            catch { $errors.Add("Could not let $($app.name) ask for ${name}: $($_.Exception.Message)") }
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalApiAuthorizations   = @($rows).Count
            CreatedApiAuthorizations = $created.Count
            ReusedApiAuthorizations  = $reused.Count
            ScopesAdded              = $scopesAdded
            ClaimsAdded              = $claimsAdded
            ClientsLinked            = $clientsLinked
            ApiAuthorizations        = (@($created) + @($reused))
            Errors                   = $errors.ToArray()
        }
    }
}
