function Get-AuthentikCredentialPath {
    <#
    .SYNOPSIS
        Resolves where the service account credential record for instance is kept

    .DESCRIPTION
        The record lives under the module's per-user credential folder, ~/.testenvironment, named
        by the instance's host, outside any working tree. Get-TestCredentialRoot creates and
        restricts that folder; this only names the file in it. Keyed by host rather than by
        anything the instance reports, because the record has to be found from the URL alone.

    .PARAMETER BaseUrl
        The instance URL the record belongs to.

    .PARAMETER Path
        An explicit path, returned unchanged, so a caller can pass a user-supplied -CredentialPath
        straight through.

    .OUTPUTS
        System.String. The record's path.

    .EXAMPLE
        PS> Get-AuthentikCredentialPath -BaseUrl 'https://auth.example.com'

        DESCRIPTION: Resolves the record path for instance
        OUTPUT: The path under ~/.testenvironment
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

    $recordHost = ([uri]$BaseUrl).Host
    if ([string]::IsNullOrWhiteSpace($recordHost)) {
        throw "'$BaseUrl' is not a usable URL; it has no host component."
    }

    $root = Get-TestCredentialRoot
    $fileName = "$recordHost.serviceaccount.json"
    $current = Join-Path -Path $root -ChildPath $fileName

    return $current
}
