function Get-PingOneDataPath {
    <#
    .SYNOPSIS
        Returns the folder holding this provider's seed data

    .DESCRIPTION
        The data sits beside the provider's code rather than at the module root, which is the
        whole point of the provider folders: a PingOne CSV is shared with nothing.

        The path comes from the provider table the root module builds at import rather than
        from $PSScriptRoot, so it still resolves when the module is loaded from a staged copy
        under out/ or from an installed location in the Gallery's folder layout.

    .OUTPUTS
        System.String, the full path to the Data folder.

    .EXAMPLE
        PS> Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneUsers.csv') -Encoding UTF8

        DESCRIPTION: Reads the seeded people
        OUTPUT: The rows
        USE CASE: Called by every step that reads its definitions from disk

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = $script:TestEnvironmentProvider['PingOne'].DataPath

    if (-not (Test-Path -LiteralPath $dataPath)) {
        throw "The PingOne provider's Data folder is missing from $dataPath. The module is incomplete."
    }

    return $dataPath
}
