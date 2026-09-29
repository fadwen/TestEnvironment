function New-OneLoginRole {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded roles that the people being seeded will hold
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
    # Passed only when given: -Tier $null fails the ValidateSet, which is how a seed with no -Tier
    # once skipped every one of these steps.
    $scope = if ($Tier) { Get-OneLoginSeedScope -Tier $Tier } else { Get-OneLoginSeedScope }

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginRoles.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    # Every role in the account carrying a name the seed would use, and separately the ones the
    # seed may reuse: empty, or holding only seeded people and apps. A prefixed role holding
    # anybody else is somebody else's, however it is named.
    $byName = @{}
    foreach ($role in @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $connection)) {
        if ($null -ne $role -and $role.name) { $byName[[string]$role.name] = $role }
    }
    $usable = @{}
    foreach ($role in @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -Connection $connection)) { $usable[[string]$role.id] = $true }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        if (-not $scope.Roles.Contains($row.Key)) {
            # Nobody in the tiers being seeded holds it, and an empty role cannot be proved ours
            # at teardown. Not made rather than made and stranded.
            Write-Verbose "Role $($row.Key) has no member in the tiers being seeded; not creating it"
            $skipped.Add($row.Key)
            continue
        }

        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        if ($byName.ContainsKey($name)) {
            $role = $byName[$name]
            if ($usable.ContainsKey([string]$role.id)) {
                Write-Verbose "Role $name already exists; reusing it"
                $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $role.id })
            }
            else {
                $errors.Add("Role '$name' already exists and holds users, apps or administrators this module did not seed. It is left alone, and nothing will be added to it.")
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin role')) { continue }

        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'roles' -Body @{ name = $name } -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id })
            Write-Verbose "Created role $name"
        }
        catch {
            # OneLogin's own words for a plan limit are "max role limit is exceed", which does not
            # say how many; the trial's number is worth saying.
            $hint = ''
            if ($_.Exception.Message -match 'limit') { $hint = ' The account''s plan allows no more roles; a OneLogin trial allows five, the Default role among them.' }
            $errors.Add("Could not create role ${name}: $($_.Exception.Message)$hint")
            Write-Warning "Could not create role ${name}: $($_.Exception.Message)$hint"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalRoles   = @($rows).Count
            CreatedRoles = $created.Count
            ReusedRoles  = $reused.Count
            SkippedRoles = $skipped.ToArray()
            Roles        = (@($created) + @($reused))
            Errors       = $errors.ToArray()
        }
    }
}
