function Get-AuthentikCredentialPath {
    <#
    .SYNOPSIS
        Resolves where the service account credential record for an instance is kept

    .DESCRIPTION
        The record lives under ~/.testenvironment, named by the instance's host, outside any
        repository working tree. A path inside the module folder would sit one .gitignore
        mistake away from being pushed. Keyed by host rather than by anything the instance
        reports about itself, so the path can be computed before a connection exists - which
        is what lets Connect-AuthentikEnvironment -ServiceAccount find the record from the
        base URL alone.

        A caller who names a path gets that path, unchanged.

    .PARAMETER BaseUrl
        The instance URL the record belongs to.

    .PARAMETER Path
        An explicit path, returned as-is when supplied.

    .OUTPUTS
        System.String. The full path of the record, which may not exist yet.

    .EXAMPLE
        PS> Get-AuthentikCredentialPath -BaseUrl https://auth.example.com

        DESCRIPTION: Computes the default record location
        OUTPUT: C:\Users\me\.testenvironment\auth.example.com.serviceaccount.json
        USE CASE: Bootstrap, connect and the credential report

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter()]
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $profileFolder = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($profileFolder)) { $profileFolder = $env:HOME }
    if ([string]::IsNullOrWhiteSpace($profileFolder)) {
        throw 'Could not determine the user profile folder. Pass -CredentialPath explicitly.'
    }

    $instanceHost = ([uri]$BaseUrl).Host
    if ([string]::IsNullOrWhiteSpace($instanceHost)) {
        throw "'$BaseUrl' is not a usable instance URL; it has no host component."
    }

    return Join-Path -Path (Join-Path -Path $profileFolder -ChildPath '.testenvironment') `
        -ChildPath "$instanceHost.serviceaccount.json"
}
