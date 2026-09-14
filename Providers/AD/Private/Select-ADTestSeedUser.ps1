function Select-ADTestSeedUser {
    <#
    .SYNOPSIS
        Chooses the user rows a seed creates and the manager assignments among them

    .DESCRIPTION
        Reads ADUsers.csv, keeps the rows in the requested tier or every row, orders them so a
        manager is created before the people who report to them, and lists the rows whose
        manager is among the rows being created.

        Held apart from New-ADTestUser because that command creates users on background jobs,
        which a unit test cannot stand in for, and the two decisions worth testing - which rows
        a tier keeps, and that a manager left out by the tier is not looked for - are made here
        without touching a directory.

        A manager is assigned only when the manager is among the rows being created. With one
        tier, a manager in the other tier is not there to point at, and looking for them in the
        directory would report an error for a person the caller chose to leave out.

    .PARAMETER Path
        The users CSV.

    .PARAMETER Tier
        Core, Bulk, or both. Nothing keeps every row.

    .EXAMPLE
        PS> Select-ADTestSeedUser -Path (Join-Path (Get-ADTestDataPath) 'ADUsers.csv') -Tier Core

        DESCRIPTION: The eleven people every provider holds, and the manager pairs among them
        OUTPUT: An object with Users and ManagerAssignments
        USE CASE: Called by New-ADTestUser before any job starts

    .OUTPUTS
        PSCustomObject with Users, the rows to create in creation order, and ManagerAssignments,
        the subset of those rows whose manager is also being created.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Tier
    )

    $rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($Tier) {
        $rows = @($rows | Where-Object { $Tier -contains $_.Tier })
    }

    # Managers before their reports, so a report's manager exists when the report is created.
    # Two passes over the file rather than a sort, because Sort-Object is not stable on Windows
    # PowerShell and -Stable does not exist there: this way two runs create the same rows in
    # the same order on both editions.
    $ordered = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Manager) }) +
        @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Manager) })

    $createdNames = @{}
    foreach ($row in $ordered) { $createdNames[$row.Name] = $true }

    $assignments = @($ordered | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Manager) -and $_.Manager -ne 'CN='
        } | Where-Object {
            $managerName = $_.Manager -replace '^CN=', ''
            if ($createdNames.ContainsKey($managerName)) { return $true }
            Write-Verbose "Not setting the manager of $($_.Name): $managerName is not among the users being created"
            $false
        })

    [PSCustomObject]@{
        Users              = $ordered
        ManagerAssignments = $assignments
    }
}
