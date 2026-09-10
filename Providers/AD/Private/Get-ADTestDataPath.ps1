function Get-ADTestDataPath {
    <#
    .SYNOPSIS
        Returns the folder holding the AD provider's seed data

    .DESCRIPTION
        Read from the provider registry the module builds at import, so the answer is the folder
        this provider was actually loaded from.

        The previous version searched a list of candidate paths and returned the first that
        existed: a relative path, a Generate-TestData folder under the current directory, and
        finally a hardcoded absolute path into one particular machine's Downloads folder. Each
        fallback is a way to silently seed a directory from a CSV nobody meant to use - the
        current-directory one fires wherever you happen to be standing, and the hardcoded one
        names a profile that exists on exactly one host. A missing Data folder is a broken
        install and should say so rather than quietly finding something else.

    .OUTPUTS
        System.String, the full path to the provider's Data folder.

    .EXAMPLE
        PS> Get-ADTestDataPath

        DESCRIPTION: Resolves the AD provider's seed data folder
        OUTPUT: C:\...\TestEnvironment\Providers\AD\Data
        USE CASE: Called by every function that imports a seed CSV

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = $script:TestEnvironmentProvider['AD'].DataPath

    if (-not (Test-Path -LiteralPath $dataPath)) {
        throw "The AD provider's Data folder is missing from $dataPath. The module is incomplete."
    }

    return $dataPath
}
