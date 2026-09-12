function New-PingOnePopulation {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded populations, which are what teardown asks rather than guessing from names
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

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOnePopulations.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $existing = @{}
    foreach ($population in (Invoke-PingOneRequest -Method GET -Path 'populations' -Paginate -Connection $connection)) {
        $existing[[string]$population.name] = $population
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        $name = Resolve-PingOneSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        if ($existing.ContainsKey($name)) {
            Write-Verbose "Population $name already exists; reusing it"
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $existing[$name].id })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create PingOne population')) { continue }

        # The tag goes in the description, which is free text nothing else in the environment
        # writes. Note what is absent: no `default`, deliberately.
        $body = @{
            name        = $name
            description = '{0} {1}' -f $row.Description, $marker.Tag
        }

        try {
            $result = Invoke-PingOneRequest -Method POST -Path 'populations' -Body $body -Connection $connection
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $result.id })
            Write-Verbose "Created population $name"
        }
        catch {
            $errors.Add("Could not create population ${name}: $($_.Exception.Message)")
            Write-Warning "Could not create population ${name}: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalPopulations   = @($rows).Count
            CreatedPopulations = $created.Count
            ReusedPopulations  = $reused.Count
            Populations        = (@($created) + @($reused))
            Errors             = $errors.ToArray()
        }
    }
}
