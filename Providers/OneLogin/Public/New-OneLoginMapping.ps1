function New-OneLoginMapping {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded user mappings, each gated so it can only ever act on seeded people
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
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    # Passed only when given: -Tier $null fails the ValidateSet, which is how a seed with no -Tier
    # once skipped every one of these steps.
    $scope = if ($Tier) { Get-OneLoginSeedScope -Tier $Tier } else { Get-OneLoginSeedScope }
    $dataPath = Get-OneLoginDataPath

    $rows = @(Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginMappings.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $roleNameByKey = @{}
    foreach ($roleRow in (Import-Csv -LiteralPath (Join-Path $dataPath 'OneLoginRoles.csv') -Encoding UTF8)) {
        $roleNameByKey[$roleRow.Key] = Resolve-OneLoginSeedName -Key $roleRow.Name -Kind DisplayName -Connection $connection
    }
    $roleByName = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -Connection $connection)) { $roleByName[[string]$role.name] = $role }

    # Every mapping, enabled or not: the endpoint lists only the enabled ones unless asked.
    $existing = @{}
    foreach ($mapping in @(
            Invoke-OneLoginRequest -Method GET -Path 'mappings' -Connection $connection | ForEach-Object { $_ }
            Invoke-OneLoginRequest -Method GET -Path 'mappings' -Query @{ enabled = 'false' } -Connection $connection | ForEach-Object { $_ }
        )) {
        if ($null -ne $mapping -and $mapping.name) { $existing[[string]$mapping.name] = $mapping }
    }

    # The gate. Written on every mapping whatever the data says, with match 'all', so the mapping
    # fires only for a user whose seed tag field holds the tag - which nobody but this module
    # writes. An enabled mapping in a production account therefore touches seeded people and no
    # one else. There is no parameter to leave it out, and a test asserts there is none.
    $gate = @{ source = ('custom_attribute_{0}' -f $script:OneLoginSeedAttribute); operator = '='; value = $marker.Tag }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        if (-not $scope.Roles.Contains($row.Role)) {
            Write-Verbose "Mapping $name adds role $($row.Role), which the tiers being seeded do not create; not creating it"
            $skipped.Add($row.Key)
            continue
        }

        if ($existing.ContainsKey($name)) {
            $mapping = $existing[$name]
            $gated = @($mapping.conditions | Where-Object {
                    $null -ne $_ -and [string]$_.source -ceq $gate.source -and [string]$_.operator -eq '=' -and
                    [string]::Equals([string]$_.value, $gate.value, [StringComparison]::Ordinal)
                }).Count -gt 0
            if ($gated -and [string]$mapping.match -eq 'all') {
                Write-Verbose "Mapping $name already exists; reusing it"
                $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $mapping.id; Enabled = [bool]$mapping.enabled })
            }
            else {
                $errors.Add("Mapping '$name' already exists without the seed-tag condition. It is somebody else's and is left alone.")
            }
            continue
        }

        $role = $roleByName[$roleNameByKey[$row.Role]]
        if (-not $role) {
            $errors.Add("Role '$($row.Role)' for mapping $name does not exist, or is not one the seed may use; run New-OneLoginRole first")
            continue
        }

        $conditions = New-Object System.Collections.Generic.List[object]
        $conditions.Add($gate)
        foreach ($entry in @(([string]$row.Conditions -split ';') | Where-Object { $_ })) {
            $parts = $entry -split '\|', 3
            if ($parts.Count -ne 3) {
                $errors.Add("Mapping $name has a condition '$entry' that is not source|operator|value")
                continue
            }
            $conditions.Add(@{ source = $parts[0]; operator = $parts[1]; value = $parts[2] })
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin mapping')) { continue }

        $body = @{
            name       = $name
            match      = 'all'
            enabled    = [bool]::Parse($row.Enabled)
            conditions = $conditions.ToArray()
            actions    = @(@{ action = 'add_role'; value = @([string]$role.id) })
        }

        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'mappings' -Body $body -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id; Enabled = $body.enabled })
            Write-Verbose "Created mapping $name"
        }
        catch {
            $errors.Add("Could not create mapping ${name}: $($_.Exception.Message)")
            Write-Warning "Could not create mapping ${name}: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalMappings   = @($rows).Count
            CreatedMappings = $created.Count
            ReusedMappings  = $reused.Count
            SkippedMappings = $skipped.ToArray()
            Mappings        = (@($created) + @($reused))
            Errors          = $errors.ToArray()
        }
    }
}
