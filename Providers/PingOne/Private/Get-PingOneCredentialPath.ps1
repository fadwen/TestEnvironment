function Get-PingOneCredentialPath {
    <#
    .SYNOPSIS
        Returns the file a worker application's secret is kept in for an environment

    .DESCRIPTION
        The record lives under the user's profile, outside the repository, and that location is
        deliberate rather than incidental: a path inside the module folder would sit in a
        working tree, one .gitignore mistake away from being pushed. It is the module's per-user
        credential folder, ~/.testenvironment.

        The file holds the secret encrypted with ConvertFrom-SecureString and nothing else - no
        client id, no environment id - because those are not secret and naming them in the file
        would make a stolen copy immediately useful. The caller names them instead.

        Encryption is the platform's. On Windows that is DPAPI, tied to the account that wrote
        it. Off Windows, PowerShell encrypts with a
        built-in key, which is obfuscation and not protection; the file permissions are what is
        doing the work there, so the folder is narrowed to the current user on creation.

    .PARAMETER EnvironmentId
        Environment the secret belongs to. Included in the file name so several environments
        can be used from one machine without overwriting each other.

    .OUTPUTS
        System.String, the full path to the record.

    .EXAMPLE
        PS> Get-PingOneCredentialPath -EnvironmentId $environmentId

        DESCRIPTION: Resolves the record path, creating the folder if needed
        OUTPUT: C:\Users\you\.testenvironment\0e2469df-....pingone.secret
        USE CASE: Called by Connect-PingOneEnvironment -UseStoredSecret

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
        [string]$EnvironmentId
    )

    # $HOME rather than $env:USERPROFILE, because the latter does not exist off Windows and the
    # module is expected to run on both.
    $root = Join-Path $HOME '.testenvironment'

    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -ItemType Directory -Path $root -Force
        try {
            if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
                $acl = Get-Acl -Path $root
                $acl.SetAccessRuleProtection($true, $false)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                    'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $acl.SetAccessRule($rule)
                Set-Acl -Path $root -AclObject $acl
            }
            else {
                & chmod 700 $root
            }
        }
        catch {
            # A record that exists with loose permissions and a loud warning is more useful
            # than one that could not be written at all.
            Write-Warning "Could not narrow the permissions on $root : $($_.Exception.Message)"
        }
    }

    return (Join-Path $root ('{0}.pingone.secret' -f $EnvironmentId))
}
