function Resolve-EntraSeededId {
    <#
    .SYNOPSIS
        Maps a seed data key to the object id it was created as

    .DESCRIPTION
        The CSV files reference each other by key - a group lists members as 'jnino', a
        Conditional Access policy scopes itself to 'dept-engineering' - and Graph needs object
        ids. This resolves one to the other by querying the tenant rather than by remembering
        what a previous step created.

        That is the whole point. Every seeding function has to work standalone, so somebody
        can rebuild just the groups over an existing set of users without re-running anything
        else. A resolver that depended on in-memory state from the same run would make each
        function only usable as part of the orchestrator.

        Lookups are cached for the lifetime of the call chain, because a full seed resolves
        the same handful of users dozens of times across groups, devices, applications and
        policies, and each miss is a network round trip.

    .PARAMETER Key
        The seed data key, for example 'jnino' or 'dept-engineering'

    .PARAMETER Kind
        Whether the key names a user or a group

    .PARAMETER Cache
        A hashtable reused across calls to avoid repeating lookups

    .PARAMETER Connection
        Connection to use instead of the module's active one

    .OUTPUTS
        System.String, the object id, or $null when the object does not exist

    .EXAMPLE
        PS> Resolve-EntraSeededId -Key jnino -Kind User -Cache $cache

        DESCRIPTION: Finds the object id of the seeded user whose key is jnino
        OUTPUT: 5ba0f0b4-6299-4ff5-893e-92d22a597ca6
        USE CASE: Turning a CSV member list into the ids Graph needs

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
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'Group')]
        [string]$Kind,

        [Parameter()]
        [hashtable]$Cache,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }
    $marker = Get-EntraSeedMarker -Connection $Connection

    $cacheKey = "$Kind::$Key"
    if ($Cache -and $Cache.ContainsKey($cacheKey)) { return $Cache[$cacheKey] }

    $id = $null

    if ($Kind -eq 'User') {
        $upn = '{0}{1}@{2}' -f $marker.Prefix, $Key, $marker.UpnSuffix
        # Addressed by UPN directly rather than filtered. It is one call either way, and a
        # direct address cannot return two results the way a filter can.
        try {
            $user = Invoke-EntraRequest -Method GET -Path "/users/$([uri]::EscapeDataString($upn))" `
                -Query @{ '$select' = 'id' } -Connection $Connection
            $id = $user.id
        }
        catch {
            Write-Verbose "No seeded user for key '$Key' ($upn): $($_.Exception.Message)"
        }
    }
    else {
        $definition = @(Get-EntraSeedData -Name 'EntraGroups') | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
        if (-not $definition) {
            Write-Verbose "No group seed definition with key '$Key'"
        }
        else {
            $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName
            # Escaped for OData, where a single quote inside a string literal is doubled. No
            # seeded name contains one today, and a resolver that breaks the first time
            # somebody adds one is a resolver that breaks silently.
            $literal = $displayName.Replace("'", "''")

            # Deliberately not called $matches. That is an automatic variable PowerShell
            # overwrites on every -match operation, so any regex evaluated between here and
            # the read below would silently replace this result with capture groups.
            $found = @(Invoke-EntraRequest -Method GET -Path '/groups' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "displayName eq '$literal'"; '$select' = 'id,displayName' })

            if ($found.Count -gt 1) {
                Write-Warning ("Found $($found.Count) groups called '$displayName'. Using the first; the " +
                    "duplicates were not created by this module or were created by an interrupted run.")
            }
            if ($found.Count -ge 1) { $id = $found[0].id }
            else { Write-Verbose "No seeded group named '$displayName'" }
        }
    }

    if ($Cache) { $Cache[$cacheKey] = $id }
    return $id
}
