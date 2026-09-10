function Get-AuthentikDataPath {
    <#
    .SYNOPSIS
        Returns the Authentik provider's Data folder

    .DESCRIPTION
        The seed CSVs live beside the provider, and their location comes from the provider
        registry the root module built at import rather than from a path relative to this
        file. Reading the registry means a staged or installed copy resolves to its own Data
        folder, and a copy that shipped without one fails here with a message naming the
        missing folder rather than later with a missing-file error per CSV.

    .OUTPUTS
        System.String. The full path of the Data folder.

    .EXAMPLE
        PS> Import-Csv -Path (Join-Path (Get-AuthentikDataPath) 'AuthentikUsers.csv') -Encoding UTF8

        DESCRIPTION: Reads a seed file
        OUTPUT: The rows of the CSV
        USE CASE: Every component function

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = $script:TestEnvironmentProvider['Authentik'].DataPath
    if (-not (Test-Path -LiteralPath $dataPath)) {
        throw "The Authentik provider's Data folder is missing from $dataPath. The module is incomplete."
    }
    return $dataPath
}
