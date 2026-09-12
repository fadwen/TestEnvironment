#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The seed's own DNS, and the one place this provider could write into a name space
    somebody depends on. What is pinned is where it writes and how it knows what is its own:
    both zones derived from the prefix and the domain, the domain's own zone never named,
    every zone stamped with the seed tag so teardown can prove it, a zone that already
    carries the seed's name without the tag refused rather than adopted, and a domain with
    no DnsServer module reported as a warning rather than a failure.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT and the DNS server cmdlets are absent on the CI runner, which leaves Pester with
    # no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ADTestSeedZone' -Tag 'Unit', 'Private' {

    It 'derives both zones from the prefix, the domain and the seed range' {
        InModuleScope TestEnvironment {
            $zone = Get-ADTestSeedZone -Marker (Get-TestSeedMarker -Prefix 'ZZ-TEST-') -Domain @{ DNSName = 'ad.contoso.com'; DomainDN = 'DC=ad,DC=contoso,DC=com' }
            $zone.Forward | Should-Be 'zz-test-lab.ad.contoso.com'
            $zone.Reverse | Should-Be '214.10.in-addr.arpa'
            $zone.NetworkId | Should-Be '10.214.0.0/16'
            # The FreeIPA provider owns 10.213, so a hybrid estate can seed both.
            $zone.Subnet | Should-NotBe '10.213'
        }
    }

    It 'refuses a domain with no DNS name rather than building a zone called nothing' {
        InModuleScope TestEnvironment {
            { Get-ADTestSeedZone -Marker (Get-TestSeedMarker -Prefix 'ZZ-TEST-') -Domain @{ DNSName = ''; DomainDN = 'DC=x' } } |
                Should-Throw -ExceptionMessage '*no DNS name*'
        }
    }
}

Describe 'New-ADTestDnsZone' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-TestProgress { }
            Mock Import-Module { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }

            $script:Zones = @{}
            $script:Calls = [System.Collections.Generic.List[object]]::new()

            Mock Get-DnsServerZone { if ($script:Zones.ContainsKey($Name)) { [PSCustomObject]@{ ZoneName = $Name } } else { $null } }
            Mock Add-DnsServerPrimaryZone {
                $script:Calls.Add(@{ Method = 'Add-Zone'; Name = $Name; NetworkId = $NetworkId })
                $key = if ($Name) { $Name } else { '214.10.in-addr.arpa' }
                $script:Zones[$key] = $true
            }
            Mock Get-ADObject { [PSCustomObject]@{ DistinguishedName = 'DC=zone,CN=MicrosoftDNS'; adminDescription = $null } }
            Mock Set-ADObject { $script:Calls.Add(@{ Method = 'Tag'; Tag = $Replace['adminDescription'] }) }
            Mock Get-DnsServerResourceRecord { $null }
            Mock Add-DnsServerResourceRecordA { $script:Calls.Add(@{ Method = 'A'; Zone = $ZoneName; Name = $Name; Address = $IPv4Address; Ptr = [bool]$CreatePtr }) }
            Mock Add-DnsServerResourceRecordCName { $script:Calls.Add(@{ Method = 'CNAME'; Zone = $ZoneName; Name = $Name; Alias = $HostNameAlias }) }
            Mock Add-DnsServerResourceRecordPtr { $script:Calls.Add(@{ Method = 'PTR'; Zone = $ZoneName; Name = $Name; Target = $PtrDomainName }) }
            Mock Add-DnsServerResourceRecord { $script:Calls.Add(@{ Method = 'TXT'; Zone = $ZoneName; Name = $Name }) }
        }
    }

    It 'creates the forward zone by name and the reverse zone from the range, and tags both so teardown can prove them' {
        InModuleScope TestEnvironment {
            $r = New-ADTestDnsZone -SkipDeviceRecords -PassThru -Confirm:$false

            $r.DnsAvailable | Should-BeTrue
            $r.ZonesCreated | Should-Be 2
            @($r.Zones.Kind) | Should-BeCollection @('Forward', 'Reverse')

            $zones = @($script:Calls | Where-Object { $_.Method -eq 'Add-Zone' })
            $zones[0].Name | Should-Be 'zz-test-lab.contoso.com'
            # The reverse zone is named by the server from the range, so no name is passed.
            [string]$zones[1].Name | Should-Be ''
            $zones[1].NetworkId | Should-Be '10.214.0.0/16'

            # Both stamped, or teardown could only remove them by name.
            @($script:Calls | Where-Object { $_.Method -eq 'Tag' } | ForEach-Object { $_.Tag }) |
                Should-BeCollection @('ZZ-TEST-seed', 'ZZ-TEST-seed')
        }
    }

    It 'never names the domain zone, and writes only into the two it derives' {
        InModuleScope TestEnvironment {
            $null = New-ADTestDnsZone -PassThru -Confirm:$false
            $touched = @($script:Calls | Where-Object { $_.Zone } | ForEach-Object { $_.Zone } | Sort-Object -Unique)
            $touched | Should-BeCollection @('214.10.in-addr.arpa', 'zz-test-lab.contoso.com')
            $touched | Should-NotContainCollection @('contoso.com')
            (Get-Command New-ADTestDnsZone).Parameters.Keys | Should-NotContainCollection @('ZoneName', 'Domain', 'Force')
        }
    }

    It 'writes an A record with its PTR for every addressed device, and the records that are not a device' {
        InModuleScope TestEnvironment {
            $r = New-ADTestDnsZone -PassThru -Confirm:$false

            # Every device in the seed carries an address, so every one gets a record.
            $devices = @(Import-Csv (Join-Path (Get-ADTestDataPath) 'ADDevices.csv') -Encoding UTF8 | Where-Object IPAddress)
            $r.DeviceRecords | Should-Be $devices.Count
            $a = @($script:Calls | Where-Object { $_.Method -eq 'A' -and $_.Ptr })
            $a.Count | Should-Be $devices.Count
            $a[0].Name | Should-MatchString '^zz-test-'
            $a[0].Address | Should-MatchString '^10\.214\.'

            # The extra records, with the prefix and the zone substituted into their targets.
            $alias = ($script:Calls | Where-Object { $_.Method -eq 'CNAME' -and $_.Name -eq 'reports' })
            $alias.Alias | Should-Be 'zz-test-sea-sql-001.zz-test-lab.contoso.com.'
            $ghost = ($script:Calls | Where-Object { $_.Method -eq 'PTR' -and $_.Name -eq '251.0' })
            $ghost.Zone | Should-Be '214.10.in-addr.arpa'
            @($script:Calls | Where-Object { $_.Method -eq 'TXT' }).Count | Should-Be 1
            @($script:Calls | Where-Object { ($_.Alias -like '*{*') -or ($_.Target -like '*{*') }) | Should-BeCollection -Count 0
        }
    }

    It 'refuses a zone that carries the seed name without the tag, and never modifies it' {
        InModuleScope TestEnvironment {
            Mock Get-DnsServerZone { if ($Name -eq 'zz-test-lab.contoso.com') { [PSCustomObject]@{ ZoneName = $Name } } else { $null } }
            Mock Get-ADObject { [PSCustomObject]@{ DistinguishedName = 'DC=zone,CN=MicrosoftDNS'; adminDescription = $null } }

            $r = New-ADTestDnsZone -SkipDeviceRecords -PassThru -Confirm:$false -ErrorAction SilentlyContinue

            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'adminDescription'
            $r.ZonesCreated | Should-Be 1
            Should-NotInvoke Add-DnsServerPrimaryZone -ParameterFilter { $Name -eq 'zz-test-lab.contoso.com' }
            # Nothing is written into a zone that is not ours.
            @($script:Calls | Where-Object { $_.Zone -eq 'zz-test-lab.contoso.com' }) | Should-BeCollection -Count 0
        }
    }

    It 'counts a zone it already owns as existing rather than creating it again' {
        InModuleScope TestEnvironment {
            Mock Get-DnsServerZone { if ($Name -eq 'zz-test-lab.contoso.com') { [PSCustomObject]@{ ZoneName = $Name } } else { $null } }
            Mock Get-ADObject { [PSCustomObject]@{ DistinguishedName = 'DC=zone,CN=MicrosoftDNS'; adminDescription = 'ZZ-TEST-seed' } }

            $r = New-ADTestDnsZone -SkipDeviceRecords -PassThru -Confirm:$false

            $r.ZonesExisting | Should-Be 1
            $r.ZonesCreated | Should-Be 1
            $r.Errors | Should-BeCollection -Count 0
        }
    }

    It 'warns and creates nothing when the DnsServer module is absent' {
        InModuleScope TestEnvironment {
            Mock Import-Module { throw 'The specified module ''DnsServer'' was not loaded.' }

            $r = New-ADTestDnsZone -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            $r.DnsAvailable | Should-BeFalse
            $r.ZonesCreated | Should-Be 0
            $r.Errors | Should-BeCollection -Count 0
            @($warnings | Where-Object { $_ -like '*DnsServer module is not available*' }).Count | Should-Be 1
            Should-NotInvoke Add-DnsServerPrimaryZone
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-ADTestDnsZone -WhatIf
            Should-NotInvoke Add-DnsServerPrimaryZone
            Should-NotInvoke Add-DnsServerResourceRecordA
            Should-NotInvoke Set-ADObject
        }
    }
}
