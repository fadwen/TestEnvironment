function Get-OktaDataPath {
    <#
    .SYNOPSIS
        Returns the folder holding the Okta provider's seed data

    .DESCRIPTION
        Read from the provider registry the module builds at import, so the answer is the folder
        this provider was actually loaded from.

        The previous version read a module-level variable and fell back to a path relative to
        its own file, which was there for the case of a file dot-sourced directly rather than
        imported. The registry removes the need for either: it is populated at import for every
        provider, so there is one answer rather than a first-match-wins search, and a missing
        Data folder is reported as the broken install it is.

    .OUTPUTS
        System.String, the full path to the provider's Data folder.

    .EXAMPLE
        PS> Get-OktaDataPath

        DESCRIPTION: Resolves the Okta provider's seed data folder
        OUTPUT: C:\...\TestEnvironment\Providers\Okta\Data
        USE CASE: Called by every function that imports a seed CSV

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = $script:TestEnvironmentProvider['Okta'].DataPath

    if (-not (Test-Path -LiteralPath $dataPath)) {
        throw "The Okta provider's Data folder is missing from $dataPath. The module is incomplete."
    }

    return $dataPath
}
