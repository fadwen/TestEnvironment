function Get-OktaCredentialPath {
    <#
    .SYNOPSIS
        Resolves where the service app's private key is stored

    .DESCRIPTION
        The default is a per-user folder outside the repository. That location is chosen so
        the private key cannot be committed by accident: a path under the module directory
        would sit inside a working tree, one .gitignore edit away from being published.

        The file name carries the org host, so credentials for two different tenants do not
        overwrite each other.

    .PARAMETER OrgUrl
        The org URL the credential belongs to

    .PARAMETER Path
        An explicit path, which is returned unchanged. Present so callers can pass a
        user-supplied -CredentialPath straight through without branching.

    .OUTPUTS
        String path to the credential file

    .EXAMPLE
        Get-OktaCredentialPath -OrgUrl 'https://trial-123456.okta.com'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OrgUrl,

        [Parameter()]
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $profileFolder = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($profileFolder)) { $profileFolder = $env:HOME }
    if ([string]::IsNullOrWhiteSpace($profileFolder)) {
        throw 'Could not determine the user profile folder. Pass -CredentialPath explicitly.'
    }

    $orgHost = ([uri]$OrgUrl).Host
    if ([string]::IsNullOrWhiteSpace($orgHost)) {
        throw "'$OrgUrl' is not a usable org URL; it has no host component."
    }

    $fileName = "$orgHost.serviceapp.json"
    $current = Join-Path -Path (Join-Path -Path $profileFolder -ChildPath '.testenvironment') -ChildPath $fileName

    # Records written by OktaTestEnvironment before the providers were consolidated live under
    # the old per-module folder. Reading falls back to it so an existing bootstrap keeps working
    # rather than being silently orphaned - the credential is still perfectly valid, and the
    # alternative is telling somebody to re-bootstrap because a folder was renamed. The Entra
    # provider does the same for its own old location.
    $legacy = Join-Path -Path (Join-Path -Path $profileFolder -ChildPath '.oktatestenvironment') -ChildPath $fileName

    if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $legacy)) {
        Write-Verbose "Using the pre-consolidation credential record at $legacy"
        return $legacy
    }

    return $current
}
