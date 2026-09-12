function New-PingOneUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded people in their populations, tags them, and applies their group memberships
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Username,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection
    $marker = Get-PingOneSeedMarker -Prefix $connection.Prefix
    $attributeName = $script:PingOneSeedAttributeName

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneUsers.csv') -Encoding UTF8)
    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($Username) { $rows = @($rows | Where-Object { $Username -contains $_.Key }) }

    # A population's display name comes from the populations file rather than from its key,
    # because 'empty-hold' is 'Offboarding Hold' and no casing rule turns one into the other.
    $populationNameByKey = @{}
    foreach ($populationRow in (Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOnePopulations.csv') -Encoding UTF8)) {
        $populationNameByKey[$populationRow.Key] = Resolve-PingOneSeedName -Key $populationRow.Name `
            -Kind DisplayName -Connection $connection
    }

    # Populations and groups, looked up once by the name the seed gave them.
    $populationId = @{}
    foreach ($population in (Invoke-PingOneRequest -Method GET -Path 'populations' -Paginate -Connection $connection)) {
        $populationId[[string]$population.name] = $population.id
    }

    $groupRows = @{}
    foreach ($groupRow in (Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneGroups.csv') -Encoding UTF8)) {
        $groupRows[$groupRow.Key] = $groupRow
    }
    $groupByName = @{}
    foreach ($group in (Invoke-PingOneRequest -Method GET -Path 'groups' -Paginate -Connection $connection)) {
        $groupByName[[string]$group.name] = $group
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $membershipsApplied = 0
    $index = 0

    foreach ($row in $rows) {
        $index++
        $login = Resolve-PingOneSeedName -Key $row.Key -Kind Username -Connection $connection
        Write-TestProgress -Activity 'Creating PingOne users' -Status $login `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        $populationName = $populationNameByKey[$row.Population]
        if (-not $populationName -or -not $populationId.ContainsKey($populationName)) {
            $errors.Add("Population '$populationName' for $login does not exist; run New-PingOnePopulation first")
            continue
        }

        $existing = @(Invoke-PingOneRequest -Method GET -Path 'users' -Connection $connection -Paginate `
                -Query @{ filter = ('username eq "{0}"' -f $login) })

        $user = $null
        if ($existing) {
            Write-Verbose "User $login already exists; reusing"
            $user = $existing[0]
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Id = $user.id })
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($login, 'Create PingOne user')) { continue }

            $body = @{
                username   = $login
                email      = Resolve-PingOneSeedName -Key $row.Key -Kind Email -Connection $connection
                population = @{ id = $populationId[$populationName] }
                enabled    = [bool]::Parse($row.Enabled)
                name       = @{}
            }
            if ($row.GivenName) { $body.name['given'] = $row.GivenName }
            if ($row.FamilyName) { $body.name['family'] = $row.FamilyName }
            if ($row.Title) { $body['title'] = $row.Title }

            $body[$attributeName] = $marker.Tag
            if ($row.BadgeId) { $body['labBadgeId'] = $row.BadgeId }
            $entitlements = @(($row.Entitlements -split ';') | Where-Object { $_ })
            if ($entitlements) { $body['labEntitlements'] = $entitlements }
            # Text on purpose, and lower case: see the description.
            $body['labContractor'] = $row.Contractor.ToLowerInvariant()
            if ($row.Department) { $body['labProfile'] = @{ department = $row.Department; tier = $row.Tier } }

            try {
                $user = Invoke-PingOneRequest -Method POST -Path 'users' -Body $body -Connection $connection
                $created.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Id = $user.id })
            }
            catch {
                $errors.Add("Could not create user ${login}: $($_.Exception.Message)")
                Write-Warning "Could not create user ${login}: $($_.Exception.Message)"
                continue
            }

            # MFA is off on a created user and has its own endpoint rather than a field.
            if ([bool]::Parse($row.MfaEnabled)) {
                try {
                    $null = Invoke-PingOneRequest -Method PUT -Path "users/$($user.id)/mfaEnabled" `
                        -Body @{ mfaEnabled = $true } -Connection $connection
                }
                catch {
                    $errors.Add("Could not enable MFA for ${login}: $($_.Exception.Message)")
                }
            }
        }

        foreach ($groupKey in @(($row.Groups -split ';') | Where-Object { $_ })) {
            $groupRow = $groupRows[$groupKey]
            if (-not $groupRow) {
                $errors.Add("Group key '$groupKey' on $login is not in the groups file")
                continue
            }
            if ($groupRow.UserFilter) {
                # PingOne maintains a filtered group's membership and refuses a manual addition.
                continue
            }

            $groupName = Resolve-PingOneSeedName -Key $groupRow.Name -Kind DisplayName -Connection $connection
            $group = $groupByName[$groupName]
            if (-not $group) {
                $errors.Add("Group '$groupName' for $login does not exist; run New-PingOneGroup first")
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$login -> $groupName", 'Add PingOne group membership')) { continue }

            try {
                $null = Invoke-PingOneRequest -Method POST -Path "users/$($user.id)/memberOfGroups" `
                    -Body @{ id = $group.id } -Connection $connection -IgnoreError 'UNIQUENESS_VIOLATION'
                $membershipsApplied++
            }
            catch {
                $errors.Add("Could not add $login to ${groupName}: $($_.Exception.Message)")
            }
        }
    }

    Write-TestProgress -Activity 'Creating PingOne users' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalUsers         = @($rows).Count
            CreatedUsers       = $created.Count
            ReusedUsers        = $reused.Count
            MembershipsApplied = $membershipsApplied
            Users              = (@($created) + @($reused))
            Errors             = $errors.ToArray()
        }
    }
}
