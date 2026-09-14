function Get-TestCredentialPath {
    <#
    .SYNOPSIS
        Returns the folder holding the bootstrapped service app's credential record

    .DESCRIPTION
        The record lives under the user's profile, outside the repository, and that location is
        deliberate rather than incidental: a path inside the module folder would sit in a
        working tree, one .gitignore mistake away from being pushed.

        The folder is created on demand with its permissions narrowed to the current user -
        inheritance broken on Windows, mode 700 elsewhere. A failure to narrow them is a
        warning rather than an error, because a credential record that exists with loose
        permissions and a loud warning is more useful than one that could not be written at
        all, and the certificate's private key is not in this file anyway.

    .PARAMETER TenantId
        Tenant the record belongs to. Included in the file name so several tenants can be
        bootstrapped from one machine without overwriting each other.

    .OUTPUTS
        System.String, the full path to the record file.

    .EXAMPLE
        PS> Get-TestCredentialPath -TenantId $tenant

        DESCRIPTION: Resolves the record path, creating the folder if needed
        OUTPUT: C:\Users\you\.testenvironment\b818de68-....serviceapp.json
        USE CASE: Called by New-TestServiceApp and Get-TestServiceApp

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
        [string]$TenantId
    )

    $root = Get-TestCredentialRoot

    # Records written by EntraTestEnvironment before the providers were consolidated live under
    # the old per-module folder. Reading falls back to it so an existing bootstrap keeps working
    # rather than being silently orphaned - the credential is still perfectly valid, and the
    # alternative is telling somebody to re-bootstrap because a folder was renamed.
    $legacyPath = Join-Path (Join-Path (Split-Path -Path $root -Parent) '.entratestenvironment') "$TenantId.serviceapp.json"
    $currentPath = Join-Path $root "$TenantId.serviceapp.json"
    if (-not (Test-Path -LiteralPath $currentPath) -and (Test-Path -LiteralPath $legacyPath)) {
        Write-Verbose "Using the pre-consolidation credential record at $legacyPath"
        return $legacyPath
    }

    return (Join-Path $root "$TenantId.serviceapp.json")
}
