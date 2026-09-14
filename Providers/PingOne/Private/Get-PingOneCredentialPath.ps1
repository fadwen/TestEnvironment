function Get-PingOneCredentialPath {
    <#
    .SYNOPSIS
        Returns the file a worker application's secret is kept in for an environment

    .DESCRIPTION
        The record lives under the module's per-user credential folder, ~/.testenvironment, which
        Get-TestCredentialRoot creates and restricts to the current user. A path inside the module
        folder would sit in a working tree, one .gitignore mistake away from being pushed.

        The file holds the secret encrypted with ConvertFrom-SecureString and nothing else - no
        client id, no environment id - because those are not secret and naming them in the file
        would make a stolen copy immediately useful. The caller names them instead. On Windows the
        encryption is DPAPI, tied to the account that wrote it; off Windows it is obfuscation, and
        the folder's permissions are what is doing the work.

    .PARAMETER EnvironmentId
        Environment the secret belongs to. Included in the file name so several environments can
        be used from one machine without overwriting each other.

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

    return (Join-Path (Get-TestCredentialRoot) ('{0}.pingone.secret' -f $EnvironmentId))
}
