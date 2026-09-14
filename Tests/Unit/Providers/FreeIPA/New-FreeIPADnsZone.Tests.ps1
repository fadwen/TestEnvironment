#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The seed's DNS is the one place it could write into somebody's production name space, so
    what is pinned is where it writes and how it knows what is its own. Both zones are named
    from the prefix and the realm's domain, the reverse zone from the seed subnet; both carry
    the SOA contact that is the seed's fingerprint; a zone already there with another contact
    is refused, never modified, never adopted; the realm's own zone is never an argument to
    anything. A realm with no DNS is a warning and an empty result, not a failure. The
    records substitute the prefix and the forward zone so an alias names a seeded host, an
    existing record is modified rather than duplicated, and the stale shapes go in as data.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}


Describe 'Get-FreeIPASeedZone' -Tag 'Unit', 'Private' {

    It 'derives both zones from the prefix, the domain and the seed subnet, and the contact from the forward zone' {
        InModuleScope TestEnvironment {
            $zone = Get-FreeIPASeedZone -Connection @{ Prefix = 'ZZ-TEST-'; Domain = 'ipa.example.com' }
            $zone.Forward | Should-Be 'zz-test-lab.ipa.example.com'
            $zone.Reverse | Should-Be '213.10.in-addr.arpa.'
            $zone.Subnet | Should-Be '10.213.0.0/16'
            $zone.Contact | Should-Be 'hostmaster.zz-test-lab.ipa.example.com.'
            (Get-FreeIPASeedZone -Connection @{ Prefix = 'AB-'; Domain = 'corp.example.org' }).Forward | Should-Be 'ab-lab.corp.example.org'
            { Get-FreeIPASeedZone -Connection @{ Prefix = 'ZZ-TEST-'; Domain = '' } } | Should-Throw -ExceptionMessage '*no domain*'
        }
    }
}

Describe 'New-FreeIPADnsZone' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            $script:ExistingZones = @{}
            $script:ExistingRecords = @{}
            # The records travel in batches; the shim records each command as one so the
            # assertions stay about the commands, and answers a lookup from the planted records.
            Mock Invoke-FreeIPABatch {
                foreach ($c in @($Command)) {
                    $script:Calls.Add(@{ Method = $c.Method; Arguments = @($c.Arguments); Options = $c.Options; IgnoreError = @($c.IgnoreError) })
                    $found = ($c.Method -eq 'dnsrecord_show' -and $script:ExistingRecords.ContainsKey($c.Arguments[1]))
                    $result = if ($found) { [PSCustomObject]@{ result = [PSCustomObject]@{ idnsname = @($c.Arguments[1]) } } } else { $null }
                    [PSCustomObject]@{ Command = $c; Success = $true; Ignored = ($c.Method -eq 'dnsrecord_show' -and -not $found); Result = $result; ErrorName = $null; ErrorMessage = $null }
                }
            }
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                switch ($Method) {
                    'dns_is_enabled' { return [PSCustomObject]@{ result = $true } }
                    'dnszone_show' {
                        if ($script:ExistingZones.ContainsKey($Arguments[0])) { return [PSCustomObject]@{ result = [PSCustomObject]@{ idnsname = @([PSCustomObject]@{ __dns_name__ = $Arguments[0] }); idnssoarname = @([PSCustomObject]@{ __dns_name__ = $script:ExistingZones[$Arguments[0]] }) } } }
                        return $null
                    }
                    'dnsrecord_show' {
                        if ($script:ExistingRecords.ContainsKey($Arguments[1])) { return [PSCustomObject]@{ result = [PSCustomObject]@{ idnsname = @($Arguments[1]) } } }
                        return $null
                    }
                    default { return [PSCustomObject]@{ result = [PSCustomObject]@{ idnsname = @($Arguments) } } }
                }
            }
        }
    }

    It 'creates the forward zone by name and the reverse zone from the subnet, both with the contact, then the records with the prefix and zone substituted' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPADnsZone -PassThru -Confirm:$false
            $r.DnsEnabled | Should-BeTrue
            $r.ZonesCreated | Should-Be 2
            $r.RecordsCreated | Should-Be 11
            $r.Errors | Should-BeCollection -Count 0
            @($r.Zones.Kind) | Should-BeCollection @('Forward', 'Reverse')

            $adds = @($script:Calls | Where-Object { $_.Method -eq 'dnszone_add' })
            $adds.Count | Should-Be 2
            $adds[0].Arguments | Should-BeCollection @('zz-test-lab.ipa.example.com')
            $adds[0].Options.idnssoarname | Should-Be 'hostmaster.zz-test-lab.ipa.example.com.'
            $adds[0].Options.idnsallowdynupdate | Should-BeFalse
            $adds[1].Arguments | Should-BeCollection -Count 0
            $adds[1].Options.name_from_ip | Should-Be '10.213.0.0/16'
            $adds[1].Options.idnssoarname | Should-Be 'hostmaster.zz-test-lab.ipa.example.com.'

            $records = @($script:Calls | Where-Object { $_.Method -eq 'dnsrecord_add' })
            $www = $records | Where-Object { $_.Arguments[1] -eq 'www' }
            $www.Arguments[0] | Should-Be 'zz-test-lab.ipa.example.com'
            @($www.Options.cnamerecord) | Should-BeCollection @('zz-test-web01.zz-test-lab.ipa.example.com.')
            $lb = $records | Where-Object { $_.Arguments[1] -eq 'lb' }
            @($lb.Options.arecord) | Should-BeCollection @('10.213.0.30', '10.213.0.31')
            $ghost = $records | Where-Object { $_.Arguments[1] -eq '251.0' }
            $ghost.Arguments[0] | Should-Be '213.10.in-addr.arpa.'
            @($ghost.Options.ptrrecord) | Should-BeCollection @('ghost01.zz-test-lab.ipa.example.com.')
            $apex = @($records | Where-Object { $_.Arguments[1] -eq '@' })
            @($apex | ForEach-Object { @($_.Options.Keys) }) | Should-BeCollection @('mxrecord', 'txtrecord')
        }
    }

    It 'never names the realm domain as a zone, and every zone argument is one of the two derived names' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPADnsZone -Confirm:$false
            $zoneArguments = @($script:Calls | Where-Object { $_.Method -like 'dnszone_*' -or $_.Method -like 'dnsrecord_*' } | ForEach-Object { $_.Arguments[0] } | Where-Object { $_ } | Sort-Object -Unique)
            $zoneArguments | Should-BeCollection @('213.10.in-addr.arpa.', 'zz-test-lab.ipa.example.com')
            $zoneArguments | Should-NotContainCollection @('ipa.example.com', 'ipa.example.com.')
            (Get-Command New-FreeIPADnsZone).Parameters.Keys | Should-NotContainCollection @('Zone', 'Domain', 'Force')
        }
    }

    It 'refuses a zone of the seed name that carries another contact, and modifies a record that exists rather than adding a second' {
        InModuleScope TestEnvironment {
            $script:ExistingZones['zz-test-lab.ipa.example.com'] = 'hostmaster.ipa.example.com.'
            $script:ExistingZones['213.10.in-addr.arpa.'] = 'hostmaster.zz-test-lab.ipa.example.com.'
            $script:ExistingRecords['251.0'] = $true
            $r = New-FreeIPADnsZone -PassThru -Confirm:$false -ErrorAction SilentlyContinue
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'hostmaster\.ipa\.example\.com'
            $r.ZonesCreated | Should-Be 0
            $r.ZonesExisting | Should-Be 1
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'dnszone_add' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'dnszone_mod' }
            # Nothing goes into the refused forward zone; the reverse zone's records still do.
            @($script:Calls | Where-Object { $_.Method -like 'dnsrecord_*' -and $_.Arguments[0] -eq 'zz-test-lab.ipa.example.com' }) | Should-BeCollection -Count 0
            @($script:Calls | Where-Object { $_.Method -eq 'dnsrecord_mod' -and $_.Arguments[1] -eq '251.0' }).Count | Should-Be 1
            @($script:Calls | Where-Object { $_.Method -eq 'dnsrecord_add' -and $_.Arguments[1] -eq '250.0' }).Count | Should-Be 1
            $r.RecordsUpdated | Should-Be 1
        }
    }

    It 'warns and creates nothing when the realm has no DNS, and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method })
                [PSCustomObject]@{ result = $false }
            }
            $r = New-FreeIPADnsZone -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            $r.DnsEnabled | Should-BeFalse
            $r.ZonesCreated | Should-Be 0
            $r.Errors | Should-BeCollection -Count 0
            @($warnings | Where-Object { $_ -like '*no DNS*' }).Count | Should-Be 1
            @($script:Calls | ForEach-Object { $_.Method }) | Should-BeCollection @('dns_is_enabled')
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPADnsZone -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -ne 'dns_is_enabled' }
        }
    }
}
