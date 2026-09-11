function Resolve-FreeIPASeedName {
    <#
    .SYNOPSIS
        Turns a seed-file key into the name the object carries in the realm

    .DESCRIPTION
        The seed files hold bare keys - 'all-staff', 'web01', 'sshd' - and the realm holds
        prefixed names. This is the one place the two are related, so that every step names
        an object the same way and teardown finds what the seed made:

        - A plain key takes the lower-case prefix: 'all-staff' becomes 'zz-test-all-staff'.
        - A host key takes the prefix and the seed's own forward zone under the connected
          realm's domain, because a FreeIPA host is its fully qualified name and a seeded
          host resolves in a zone the seed owns: 'web01' becomes
          'zz-test-web01.zz-test-lab.ipa.example.com'.
        - A key written 'builtin:sshd' names an object FreeIPA created at install, which the
          seed may reference but never creates or changes, and it is returned as 'sshd'.
        - A sudo command is its path and cannot be prefixed, so a key starting with '/' is
          returned as it is.

    .PARAMETER Key
        The key as the seed file has it.

    .PARAMETER Kind
        Name for a prefixed name, Host for a fully qualified host name, Command for a sudo
        command path.

    .PARAMETER Marker
        The seed marker to derive from. Defaults to the active connection's.

    .PARAMETER Connection
        The connection whose domain a host name takes. Defaults to the active one.

    .OUTPUTS
        System.String. The name in the realm.

    .EXAMPLE
        PS> Resolve-FreeIPASeedName -Key 'web01' -Kind Host

        DESCRIPTION: Resolves a host key to its fully qualified name
        OUTPUT: zz-test-web01.ipa.example.com
        USE CASE: Every step that creates or references a host

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Key,

        [Parameter()]
        [ValidateSet('Name', 'Host', 'Command')]
        [string]$Kind = 'Name',

        [Parameter()]
        [PSObject]$Marker,

        [Parameter()]
        [hashtable]$Connection
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }
    if ($Key.StartsWith('builtin:', [StringComparison]::OrdinalIgnoreCase)) { return $Key.Substring(8) }
    if ($Kind -eq 'Command' -or $Key.StartsWith('/')) { return $Key }

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }
    if (-not $Marker) { $Marker = Get-FreeIPASeedMarker -Connection $Connection }

    $name = '{0}{1}' -f $Marker.NamePrefix, $Key.ToLowerInvariant()
    if ($Kind -eq 'Host') {
        if ([string]::IsNullOrWhiteSpace($Connection.Domain)) {
            throw 'The connection carries no domain, so a host name cannot be resolved.'
        }
        return '{0}.{1}' -f $name, (Get-FreeIPASeedZone -Marker $Marker -Connection $Connection).Forward
    }
    return $name
}
