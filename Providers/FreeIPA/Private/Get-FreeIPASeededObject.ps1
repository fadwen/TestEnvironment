function Get-FreeIPASeededObject {
    <#
    .SYNOPSIS
        Finds the objects of one type that this module created, and nothing else

    .DESCRIPTION
        Teardown and the report both need the same answer: which of the objects in the realm
        are ours. FreeIPA has no container to ask, so each type has to satisfy the evidence
        the module wrote when it created the object:

        - Users carry the seed tag in their userclass attribute, which user-find filters on
          server-side. Human logins carry no prefix, so this is the only evidence they have.
          Staged users are a separate container and a separate search; preserved users are
          found by asking for them. The automation service account is a tagged user with a
          reserved login and is excluded unless -IncludeServiceAccount is passed, because it
          is the credential the session is using.
        - Hosts carry the tag in userclass AND the prefix on the fully qualified name.
        - Groups and host groups carry the prefix on the name AND the bracketed marker in
          their description. A group named like ours by an administrator, without the marker,
          is left alone.

    .PARAMETER Type
        Which objects to find.

    .PARAMETER IncludeServiceAccount
        For Users: include the module's own automation account.

    .PARAMETER Detail
        Ask for every attribute rather than the default listing. The report needs it; a
        teardown does not.

    .PARAMETER Connection
        The connection to look through. Defaults to the active one.

    .OUTPUTS
        System.Object[]. The entries as FreeIPA returned them, or an empty array.

    .EXAMPLE
        PS> Get-FreeIPASeededObject -Type Users

        DESCRIPTION: Lists the seeded users
        OUTPUT: Every active or disabled user carrying the tag, minus the automation account
        USE CASE: Membership resolution in the seed steps, and the users step of teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Users', 'StagedUsers', 'PreservedUsers', 'Groups', 'Hosts', 'Hostgroups')]
        [string]$Type,

        [Parameter()]
        [switch]$IncludeServiceAccount,

        [Parameter()]
        [switch]$Detail,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }
    $marker = Get-FreeIPASeedMarker -Connection $Connection
    $prefix = $marker.NamePrefix

    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { [string]$value } }

    $hasTag = {
        param($entry)
        $entry.PSObject.Properties[$marker.Attribute] -and (@($entry.($marker.Attribute)) -contains $marker.Tag)
    }
    # A string method rather than -like: the marker's square brackets are wildcard characters
    # to -like, which would refuse the pattern and find nothing.
    $hasMarker = {
        param($entry)
        $entry.PSObject.Properties['description'] -and ((& $first $entry.description).Contains($marker.Marker))
    }
    $startsWithPrefix = {
        param($name)
        $name -and ([string]$name).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    }

    $options = @{}
    if ($Detail) { $options['all'] = $true }

    switch ($Type) {
        'Users' {
            $serviceAccount = Get-FreeIPAServiceAccountName -Marker $marker
            $options[$marker.Attribute] = $marker.Tag
            $users = @(Invoke-FreeIPARequest -Method 'user_find' -Options $options -Find -Connection $Connection)
            return @($users | Where-Object {
                    (& $hasTag $_) -and
                    ($IncludeServiceAccount -or (& $first $_.uid) -ne $serviceAccount)
                })
        }
        'StagedUsers' {
            $options[$marker.Attribute] = $marker.Tag
            $users = @(Invoke-FreeIPARequest -Method 'stageuser_find' -Options $options -Find -Connection $Connection)
            return @($users | Where-Object { & $hasTag $_ })
        }
        'PreservedUsers' {
            $options[$marker.Attribute] = $marker.Tag
            $options['preserved'] = $true
            $users = @(Invoke-FreeIPARequest -Method 'user_find' -Options $options -Find -Connection $Connection)
            return @($users | Where-Object { & $hasTag $_ })
        }
        'Groups' {
            $groups = @(Invoke-FreeIPARequest -Method 'group_find' -Arguments $prefix -Options $options -Find -Connection $Connection)
            return @($groups | Where-Object { (& $startsWithPrefix (& $first $_.cn)) -and (& $hasMarker $_) })
        }
        'Hostgroups' {
            $hostgroups = @(Invoke-FreeIPARequest -Method 'hostgroup_find' -Arguments $prefix -Options $options -Find -Connection $Connection)
            return @($hostgroups | Where-Object { (& $startsWithPrefix (& $first $_.cn)) -and (& $hasMarker $_) })
        }
        'Hosts' {
            $options[$marker.Attribute] = $marker.Tag
            $hosts = @(Invoke-FreeIPARequest -Method 'host_find' -Options $options -Find -Connection $Connection)
            return @($hosts | Where-Object { (& $hasTag $_) -and (& $startsWithPrefix (& $first $_.fqdn)) })
        }
    }
}
