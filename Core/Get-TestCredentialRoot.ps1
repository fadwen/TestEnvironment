function Get-TestCredentialRoot {
    <#
    .SYNOPSIS
        Returns the module's per-user credential folder, creating and restricting it on first use

    .DESCRIPTION
        Every provider that keeps a durable credential - a service app's key, a service account's
        token or password, a worker application's secret - writes it under ~/.testenvironment,
        outside any working tree, so it is never one .gitignore mistake away from being pushed.
        This is the one place that folder is created, and it is restricted to the current user
        before anything lands in it: an ACL with inheritance broken and a single full-control
        entry on Windows, chmod 700 elsewhere.

        $HOME rather than $env:USERPROFILE, because the latter does not exist off Windows and the
        module runs on both.

    .OUTPUTS
        System.String. The folder's path.

    .EXAMPLE
        PS> Join-Path (Get-TestCredentialRoot) 'auth.example.com.serviceaccount.json'

        DESCRIPTION: Resolves where a provider's record lives
        OUTPUT: The path under the user's profile
        USE CASE: Every Get-<Provider>CredentialPath

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    $profileFolder = $HOME
    if ([string]::IsNullOrWhiteSpace($profileFolder)) { $profileFolder = [Environment]::GetFolderPath('UserProfile') }
    if ([string]::IsNullOrWhiteSpace($profileFolder)) { $profileFolder = $env:HOME }
    if ([string]::IsNullOrWhiteSpace($profileFolder)) {
        throw 'Could not determine the user profile folder. Pass -CredentialPath explicitly.'
    }

    $root = Join-Path $profileFolder '.testenvironment'
    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -Path $root -ItemType Directory -Force
        # A folder that exists with loose permissions and a loud warning is more useful than one
        # that could not be created at all.
        if (-not (Protect-TestFile -Path $root -Confirm:$false)) {
            Write-Warning "Created $root but could not narrow its permissions."
        }
    }

    return $root
}
