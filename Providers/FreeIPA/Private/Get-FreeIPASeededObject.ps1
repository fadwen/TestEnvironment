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
        - Groups, host groups, netgroups, HBAC services and service groups, HBAC rules, sudo
          command groups, sudo rules, privileges and roles carry the prefix on the name AND
          the bracketed marker in their description. A rule named like ours by an
          administrator, without the marker, is left alone.
        - Sudo commands are named by their path and cannot carry a prefix, so the marker in
          the description is the whole proof, and a command that already existed without it
          is never ours.
        - Permissions, service delegation rules and targets, and automount locations have no
          description, so the prefix on the name is all they can carry.
        - ID views, OTP tokens, automember rules, SELinux user maps and certificate mapping
          rules carry the prefix on their name or identifier AND the marker in their
          description. An automember rule is found once per kind and tagged with the kind,
          because the API keeps group rules and host group rules apart.
        - Password policies are keyed by the group they apply to, so a policy is ours when
          its group is a seeded group.
        - Services carry the prefix on the host part of the principal and belong to a seeded
          host.

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
        [ValidateSet('Users', 'StagedUsers', 'PreservedUsers', 'Groups', 'Hosts', 'Hostgroups', 'Netgroups',
            'HbacServices', 'HbacServiceGroups', 'HbacRules', 'SudoCommands', 'SudoCommandGroups', 'SudoRules',
            'Permissions', 'Privileges', 'Roles', 'PasswordPolicies', 'Services', 'ServiceDelegationRules',
            'ServiceDelegationTargets', 'IdViews', 'OtpTokens', 'AutomemberRules', 'AutomountLocations', 'SelinuxUserMaps',
            'CertMapRules', 'CaAcls', 'Certificates', 'DnsZones', 'DnsRecords')]
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

    # The common shape: a find by the prefix as the search string, then the prefix on cn and
    # the marker in the description.
    $prefixedWithMarker = {
        param($method)
        $entries = @(Invoke-FreeIPARequest -Method $method -Arguments $prefix -Options $options -Find -Connection $Connection)
        return @($entries | Where-Object { (& $startsWithPrefix (& $first $_.cn)) -and (& $hasMarker $_) })
    }
    $prefixedOnly = {
        param($method)
        $entries = @(Invoke-FreeIPARequest -Method $method -Arguments $prefix -Options $options -Find -Connection $Connection)
        return @($entries | Where-Object { & $startsWithPrefix (& $first $_.cn) })
    }

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
        'Groups' { return & $prefixedWithMarker 'group_find' }
        'Hostgroups' { return & $prefixedWithMarker 'hostgroup_find' }
        'Hosts' {
            $options[$marker.Attribute] = $marker.Tag
            $hosts = @(Invoke-FreeIPARequest -Method 'host_find' -Options $options -Find -Connection $Connection)
            return @($hosts | Where-Object { (& $hasTag $_) -and (& $startsWithPrefix (& $first $_.fqdn)) })
        }
        'Netgroups' { return & $prefixedWithMarker 'netgroup_find' }
        'HbacServices' { return & $prefixedWithMarker 'hbacsvc_find' }
        'HbacServiceGroups' { return & $prefixedWithMarker 'hbacsvcgroup_find' }
        'HbacRules' { return & $prefixedWithMarker 'hbacrule_find' }
        'SudoCommands' {
            # Searched by the marker, since the name is a path. The description is the proof.
            $commands = @(Invoke-FreeIPARequest -Method 'sudocmd_find' -Arguments $marker.Marker -Options $options -Find -Connection $Connection)
            return @($commands | Where-Object { & $hasMarker $_ })
        }
        'SudoCommandGroups' { return & $prefixedWithMarker 'sudocmdgroup_find' }
        'SudoRules' { return & $prefixedWithMarker 'sudorule_find' }
        'Permissions' { return & $prefixedOnly 'permission_find' }
        'Privileges' { return & $prefixedWithMarker 'privilege_find' }
        'Roles' { return & $prefixedWithMarker 'role_find' }
        'PasswordPolicies' {
            $groupNames = @((Get-FreeIPASeededObject -Type Groups -Connection $Connection) | ForEach-Object { & $first $_.cn })
            $policies = @(Invoke-FreeIPARequest -Method 'pwpolicy_find' -Arguments $prefix -Options $options -Find -Connection $Connection)
            return @($policies | Where-Object { $groupNames -contains (& $first $_.cn) })
        }
        'Services' {
            $hostNames = @((Get-FreeIPASeededObject -Type Hosts -Connection $Connection) | ForEach-Object { & $first $_.fqdn })
            $services = @(Invoke-FreeIPARequest -Method 'service_find' -Arguments $prefix -Options $options -Find -Connection $Connection)
            return @($services | Where-Object {
                    $principal = & $first $_.krbcanonicalname
                    if (-not $principal -and $_.PSObject.Properties['krbprincipalname']) { $principal = & $first $_.krbprincipalname }
                    $serviceHost = (($principal -split '@')[0] -split '/', 2)[-1]
                    (& $startsWithPrefix $serviceHost) -and ($hostNames -contains $serviceHost)
                })
        }
        'ServiceDelegationRules' { return & $prefixedOnly 'servicedelegationrule_find' }
        'ServiceDelegationTargets' { return & $prefixedOnly 'servicedelegationtarget_find' }
        'IdViews' { return & $prefixedWithMarker 'idview_find' }
        'OtpTokens' {
            $tokens = @(Invoke-FreeIPARequest -Method 'otptoken_find' -Arguments $prefix -Options $options -Find -Connection $Connection)
            return @($tokens | Where-Object { (& $startsWithPrefix (& $first $_.ipatokenuniqueid)) -and (& $hasMarker $_) })
        }
        'AutomemberRules' {
            $found = foreach ($kind in 'group', 'hostgroup') {
                $kindOptions = @{ type = $kind }
                foreach ($key in $options.Keys) { $kindOptions[$key] = $options[$key] }
                @(Invoke-FreeIPARequest -Method 'automember_find' -Arguments $prefix -Options $kindOptions -Find -NoLimit -Connection $Connection) |
                    Where-Object { (& $startsWithPrefix (& $first $_.cn)) -and (& $hasMarker $_) } |
                    ForEach-Object { Add-Member -InputObject $_ -NotePropertyName 'automembertype' -NotePropertyValue $kind -Force -PassThru }
            }
            return @($found)
        }
        'AutomountLocations' { return & $prefixedOnly 'automountlocation_find' }
        'SelinuxUserMaps' { return & $prefixedWithMarker 'selinuxusermap_find' }
        'CertMapRules' { return & $prefixedWithMarker 'certmaprule_find' }
        'CaAcls' { return & $prefixedWithMarker 'caacl_find' }
        'DnsZones' {
            # A zone is ours by its SOA contact, which only the seed writes, and by being one
            # of the two names the seed derives; a reverse zone's name cannot carry a prefix.
            $zone = Get-FreeIPASeedZone -Marker $marker -Connection $Connection
            $options['idnssoarname'] = $zone.Contact
            $zones = @(Invoke-FreeIPARequest -Method 'dnszone_find' -Options $options -Find -Connection $Connection)
            $ours = @(($zone.Forward.TrimEnd('.') + '.'), $zone.Reverse)
            return @($zones | Where-Object {
                    (ConvertFrom-FreeIPADnsName -Value $_.idnssoarname) -eq $zone.Contact -and $ours -contains (ConvertFrom-FreeIPADnsName -Value $_.idnsname)
                } | ForEach-Object {
                    $kind = if ((ConvertFrom-FreeIPADnsName -Value $_.idnsname) -eq $zone.Reverse) { 'Reverse' } else { 'Forward' }
                    Add-Member -InputObject $_ -NotePropertyName 'zonekind' -NotePropertyValue $kind -Force -PassThru
                })
        }
        'DnsRecords' {
            $found = foreach ($seededZone in @(Get-FreeIPASeededObject -Type DnsZones -Connection $Connection)) {
                $zoneName = ConvertFrom-FreeIPADnsName -Value $seededZone.idnsname
                @(Invoke-FreeIPARequest -Method 'dnsrecord_find' -Arguments $zoneName -Options $options -Find -Connection $Connection) |
                    ForEach-Object { Add-Member -InputObject $_ -NotePropertyName 'zonename' -NotePropertyValue $zoneName -Force -PassThru }
            }
            return @($found)
        }
        'Certificates' {
            # A certificate has no description and a user certificate's subject is the bare
            # login, so the proof is the owner. The CA is asked one owner at a time, because
            # cert_find given two owners returns what both hold, not what either does; and
            # only for the seeded entries that carry a certificate at all, which the full
            # listings show, so three hundred users cost three calls and not three hundred.
            # The full record is always asked for: without it the serial number arrives as
            # a JSON number too large for Windows PowerShell to keep exact.
            $owners = @(
                @{ Option = 'user'; Attribute = 'uid'; Entries = @(Get-FreeIPASeededObject -Type Users -IncludeServiceAccount -Detail -Connection $Connection) }
                @{ Option = 'service'; Attribute = 'krbcanonicalname'; Entries = @(Get-FreeIPASeededObject -Type Services -Detail -Connection $Connection) }
                @{ Option = 'host'; Attribute = 'fqdn'; Entries = @(Get-FreeIPASeededObject -Type Hosts -Detail -Connection $Connection) }
            )
            $seen = @{}
            $found = foreach ($owner in $owners) {
                $holders = @($owner.Entries | Where-Object { $_.PSObject.Properties['usercertificate'] -and @($_.usercertificate).Count -gt 0 } | ForEach-Object { & $first $_.($owner.Attribute) } | Where-Object { $_ })
                foreach ($holder in $holders) {
                    $searchOptions = @{ all = $true }
                    $searchOptions[$owner.Option] = [object[]]@($holder)
                    foreach ($cert in @(Invoke-FreeIPARequest -Method 'cert_find' -Options $searchOptions -Find -Connection $Connection)) {
                        $serial = & $first $cert.serial_number
                        if ($seen.ContainsKey($serial)) { continue }
                        $seen[$serial] = $true
                        Add-Member -InputObject $cert -NotePropertyName 'ownerkind' -NotePropertyValue $owner.Option -Force -PassThru
                    }
                }
            }
            return @($found)
        }
    }
}
