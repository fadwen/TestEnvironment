#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every seeded host is a record and never a machine, and the two things that would make it
    otherwise are pinned: the add is forced, so the realm's DNS is never consulted or
    written, and nothing here ever touches a keytab. Beyond that: the fully qualified name
    under the realm's domain, the tag and the class in userclass, the list attributes sent as
    lists, membership one call per host group after every host exists, and the managed-by
    relationship applied only once both hosts exist.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAHost' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            $script:ZoneExists = $true
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_add_member' -or $Method -eq 'host_add_managedby') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                if ($Method -eq 'dnszone_show') { if ($script:ZoneExists) { return [PSCustomObject]@{ result = [PSCustomObject]@{ idnsname = @($Arguments[0]) } } } else { return $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ fqdn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates every host as a forced record in the seed zone, with the tag and class in userclass and the address the row gives' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAHost -HostName web01, bastion01, orphan01 -PassThru -Confirm:$false

            $r.CreatedHosts | Should-Be 3
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'host_add' })
            $adds.Arguments | Should-BeCollection @('zz-test-web01.zz-test-lab.ipa.example.com', 'zz-test-bastion01.zz-test-lab.ipa.example.com', 'zz-test-orphan01.zz-test-lab.ipa.example.com')
            foreach ($add in $adds) {
                $add.Options.force | Should-BeTrue
                $add.Options.description | Should-MatchString '\[ZZ-TEST-seed\]'
            }
            # The zone is looked up once, by the seed's name, and the address goes to FreeIPA
            # for it to write the A and PTR records; the host with no address gets none.
            $zoneLookups = @($script:Calls | Where-Object { $_.Method -eq 'dnszone_show' })
            $zoneLookups.Count | Should-Be 1
            $zoneLookups[0].Arguments | Should-BeCollection @('zz-test-lab.ipa.example.com')
            $web = ($adds | Where-Object { $_.Arguments[0] -like 'zz-test-web01.*' }).Options
            $web.ip_address | Should-Be '10.213.0.11'
            ($adds | Where-Object { $_.Arguments[0] -like 'zz-test-orphan01.*' }).Options.ContainsKey('ip_address') | Should-BeFalse
            $web.userclass | Should-BeCollection @('ZZ-TEST-seed', 'server')
            $web.nsosversion | Should-Be 'Rocky Linux 9.4'
            $web.ipasshpubkey.Count | Should-Be 1
            $web.macaddress | Should-BeCollection @('52:54:00:1a:2b:01')
            ($adds | Where-Object { $_.Arguments[0] -like 'zz-test-bastion01.*' }).Options.krbprincipalauthind | Should-BeCollection @('otp')
            $orphan = ($adds | Where-Object { $_.Arguments[0] -like 'zz-test-orphan01.*' }).Options
            $orphan.userclass | Should-BeCollection @('ZZ-TEST-seed')
            $orphan.description | Should-Be '[ZZ-TEST-seed]'
            $orphan.ContainsKey('nsosversion') | Should-BeFalse
        }
    }

    It 'places hosts one call per host group after every host exists, and applies managed-by only when both hosts exist' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAHost -HostName web01, db01, nfs01 -PassThru -Confirm:$false

            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'host_add') | Should-BeLessThan ([array]::IndexOf($methods, 'hostgroup_add_member'))
            $memberships = @($script:Calls | Where-Object { $_.Method -eq 'hostgroup_add_member' })
            @($memberships.Arguments | Sort-Object) | Should-BeCollection @('zz-test-all-servers', 'zz-test-db-servers', 'zz-test-web-servers')
            ($memberships | Where-Object { $_.Arguments[0] -eq 'zz-test-all-servers' }).Options.host | Should-BeCollection @('zz-test-nfs01.zz-test-lab.ipa.example.com')
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'host_add_managedby' -and $Arguments[0] -eq 'zz-test-db01.zz-test-lab.ipa.example.com' -and $Options.host -contains 'zz-test-web01.zz-test-lab.ipa.example.com' }
            $r.MembershipsApplied | Should-Be 3
        }
    }

    It 'leaves a host unmanaged, with a warning, when its manager neither exists nor is selected' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHost -HostName db01 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'host_add_managedby' }
            @($warnings | Where-Object { $_ -like "*managed by 'web01'*" }).Count | Should-Be 1
        }
    }

    It 'creates the hosts without addresses, with one warning, when the seed zone is not there' {
        InModuleScope TestEnvironment {
            $script:ZoneExists = $false
            $r = New-FreeIPAHost -HostName web01, db01 -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            $r.CreatedHosts | Should-Be 2
            @($script:Calls | Where-Object { $_.Method -eq 'host_add' -and $_.Options.ContainsKey('ip_address') }).Count | Should-Be 0
            @($warnings | Where-Object { $_ -like '*without addresses*' }).Count | Should-Be 1
        }
    }

    It 'modifies a host that exists without forcing' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ fqdn = @('zz-test-web01.zz-test-lab.ipa.example.com'); userclass = @('ZZ-TEST-seed', 'server') }) }
            $r = New-FreeIPAHost -HostName web01 -PassThru -Confirm:$false
            $r.UpdatedHosts | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'host_mod' -and -not $Options.ContainsKey('force') -and $IgnoreError -contains 'EmptyModlist' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'host_add' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHost -Tier Core -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }

    It 'never writes DNS itself, only reads the seed zone, and never touches a keytab through any method it calls' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHost -Tier Core -Confirm:$false
            $methods = @($script:Calls | ForEach-Object { $_.Method } | Sort-Object -Unique)
            # The A and PTR records are FreeIPA's to write from the address on host_add, into
            # the seed's zone; no dnsrecord or dnszone write ever leaves here.
            @($methods | Where-Object { $_ -like 'dns*' }) | Should-BeCollection @('dnszone_show')
            @($methods | Where-Object { $_ -like '*keytab*' -or $_ -like '*enroll*' }) | Should-BeCollection -Count 0
        }
    }
}
