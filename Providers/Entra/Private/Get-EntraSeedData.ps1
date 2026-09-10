function Get-EntraSeedData {
    <#
    .SYNOPSIS
        Imports one of the module's seed data CSV files as UTF-8

    .DESCRIPTION
        Every seed definition lives in Data\*.csv so the shape of the environment can be
        changed without editing code, and so the contract tests can assert on it directly.

        The encoding is stated explicitly rather than left to the default, and that is not
        cosmetic. Several rows carry accented names deliberately - Zoë, Niño, Álvarez - and
        Windows PowerShell's Import-Csv defaults to the ANSI code page, which turns them into
        different characters without raising anything. The resulting directory looks almost
        right, which is worse than looking wrong.

        A missing file is an error rather than an empty result. An empty result would make
        the seeding step succeed having created nothing, and report success for it.

    .PARAMETER Name
        The file's base name, without the .csv extension, for example EntraUsers

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]

    .EXAMPLE
        PS> Get-EntraSeedData -Name EntraUsers

        DESCRIPTION: Loads the nine seed user definitions
        OUTPUT: One object per row, with the CSV headers as properties
        USE CASE: Called by New-EntraUser and by the report

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    # Read from the provider registry the module built at import, rather than from a path
    # Connect-TestEnvironment copies into module state. A copy is only correct while a session
    # is connected, which makes reading seed data - something that needs no tenant at all -
    # depend on having authenticated first, for no reason beyond where the value was kept.
    $path = Join-Path -Path $script:TestEnvironmentProvider['Entra'].DataPath -ChildPath "$Name.csv"
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "Seed data file not found: $path" -ErrorAction Stop
        return
    }

    $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8)
    if ($rows.Count -eq 0) {
        Write-Error "Seed data file $path parsed to no rows." -ErrorAction Stop
        return
    }

    Write-Verbose "Loaded $($rows.Count) row(s) from $Name.csv"
    return $rows
}
