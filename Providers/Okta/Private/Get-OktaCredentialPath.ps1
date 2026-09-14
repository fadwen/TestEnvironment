function Get-OktaCredentialPath {
    <#
    .SYNOPSIS
        Resolves where the service account credential record for org is kept

    .DESCRIPTION
        The record lives under the module's per-user credential folder, ~/.testenvironment, named
        by the org's host, outside any working tree. Get-TestCredentialRoot creates and
        restricts that folder; this only names the file in it. Keyed by host rather than by
        anything the org reports, because the record has to be found from the URL alone.

    .PARAMETER OrgUrl
        The org URL the record belongs to.

    .PARAMETER Path
        An explicit path, returned unchanged, so a caller can pass a user-supplied -CredentialPath
        straight through.

    .OUTPUTS
        System.String. The record's path.

    .EXAMPLE
        PS> Get-OktaCredentialPath -OrgUrl 'https://trial-123456.okta.com'

        DESCRIPTION: Resolves the record path for org
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
        [string]$OrgUrl,

        [Parameter()]
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $recordHost = ([uri]$OrgUrl).Host
    if ([string]::IsNullOrWhiteSpace($recordHost)) {
        throw "'$OrgUrl' is not a usable URL; it has no host component."
    }

    $root = Get-TestCredentialRoot
    $fileName = "$recordHost.serviceapp.json"
    $current = Join-Path -Path $root -ChildPath $fileName

    # Records written by the module this provider was split from live under the old per-module
    # folder. Reading falls back to it so an existing bootstrap keeps working rather than being
    # silently orphaned: the credential is still valid, and the alternative is telling somebody to
    # re-bootstrap because a folder was renamed.
    $legacy = Join-Path -Path (Join-Path -Path (Split-Path -Path $root -Parent) -ChildPath '.oktatestenvironment') -ChildPath $fileName
    if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $legacy)) {
        Write-Verbose "Using the pre-consolidation credential record at $legacy"
        return $legacy
    }

    return $current
}
