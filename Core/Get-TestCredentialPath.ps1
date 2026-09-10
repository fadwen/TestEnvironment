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

    # $HOME rather than $env:USERPROFILE, because the latter does not exist off Windows and the
    # module is expected to run on both.
    $root = Join-Path $HOME '.testenvironment'

    # Records written by EntraTestEnvironment before the providers were consolidated live under
    # the old per-module folder. Reading falls back to it so an existing bootstrap keeps working
    # rather than being silently orphaned - the credential is still perfectly valid, and the
    # alternative is telling somebody to re-bootstrap because a folder was renamed.
    $legacyRoot = Join-Path $HOME '.entratestenvironment'
    $legacyPath = Join-Path $legacyRoot "$TenantId.serviceapp.json"
    $currentPath = Join-Path $root "$TenantId.serviceapp.json"

    if (-not (Test-Path -LiteralPath $currentPath) -and (Test-Path -LiteralPath $legacyPath)) {
        Write-Verbose "Using the pre-consolidation credential record at $legacyPath"
        return $legacyPath
    }

    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -Path $root -ItemType Directory -Force

        try {
            if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
                $acl = Get-Acl -Path $root
                $acl.SetAccessRuleProtection($true, $false)
                foreach ($rule in @($acl.Access)) { $null = $acl.RemoveAccessRule($rule) }
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                        'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
                Set-Acl -Path $root -AclObject $acl
            }
            else {
                # Get-Command can return several matches for chmod on some distributions, so
                # the first is selected explicitly. Taking .Source off a collection silently
                # invokes nothing at all.
                $chmod = @(Get-Command chmod -ErrorAction SilentlyContinue) | Select-Object -First 1
                if ($chmod) { & $chmod.Source 700 $root }
            }
        }
        catch {
            Write-Warning "Created $root but could not narrow its permissions: $($_.Exception.Message)"
        }
    }

    return (Join-Path $root "$TenantId.serviceapp.json")
}
