function New-OneLoginGroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded groups that the people being seeded will be placed in
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

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginGroups.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $byName = @{}
    foreach ($group in @(Invoke-OneLoginRequest -Method GET -Path 'groups' -Paginate -Connection $connection)) {
        if ($null -ne $group -and $group.name) { $byName[[string]$group.name] = $group }
    }
    $usable = @{}
    foreach ($group in @(Get-OneLoginSeededObject -Type Groups -AllowEmpty -Connection $connection)) { $usable[[string]$group.id] = $true }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        if (-not $scope.Groups.Contains($row.Key)) {
            Write-Verbose "Group $($row.Key) has no member in the tiers being seeded; not creating it"
            $skipped.Add($row.Key)
            continue
        }

        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        if ($byName.ContainsKey($name)) {
            $group = $byName[$name]
            if ($usable.ContainsKey([string]$group.id)) {
                Write-Verbose "Group $name already exists; reusing it"
                $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $group.id })
            }
            else {
                $errors.Add("Group '$name' already exists and holds users, a policy or administrators this module did not seed. It is left alone, and nobody will be put in it.")
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin group')) { continue }

        # A name and nothing else. No policy: the seed creates none, and attaching one that exists
        # would change how its real members sign in.
        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'groups' -Body @{ name = $name } -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id })
            Write-Verbose "Created group $name"
        }
        catch {
            $errors.Add("Could not create group ${name}: $($_.Exception.Message)")
            Write-Warning "Could not create group ${name}: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalGroups   = @($rows).Count
            CreatedGroups = $created.Count
            ReusedGroups  = $reused.Count
            SkippedGroups = $skipped.ToArray()
            Groups        = (@($created) + @($reused))
            Errors        = $errors.ToArray()
        }
    }
}
