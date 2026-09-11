#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The identity detail over the directory. Pinned for ID views: the view before its
    overrides, a user anchored by login and a group by its realm name, only the fields a row
    fills sent, the view applied to its hosts after the overrides exist, and the Default
    Trust View never named. For tokens: enrolled on the owner, the secret never kept or
    returned, the QR code suppressed, the disabled and expired states, and the immutable
    fields left alone on a re-run. For automember: rules and conditions with the exclusive
    regex kept apart, and the rebuild scoped to the seeded users and hosts by name in batches,
    never the realm at large. For automount: the location, maps and keys with the NFS host
    substituted for the realm's domain and the session's prefix, in the map FreeIPA created
    with the location. For SELinux maps: a rule-scoped map with no members and a member-scoped
    map with no rule. For certificate mapping: the domain escaped in the match rule and the
    disabled rule disabled.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAIdView' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_show') { return $null }
                if ($Method -eq 'idview_apply') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates the view, then its overrides with only the fields each row fills, then applies it' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAIdView -ViewName legacy-view -PassThru -Confirm:$false
            $r.CreatedViews | Should-Be 1
            $r.OverridesCreated | Should-Be 3
            $r.HostsApplied | Should-Be 1
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::IndexOf($methods, 'idview_add') | Should-BeLessThan ([array]::IndexOf($methods, 'idoverrideuser_add'))
            [array]::LastIndexOf($methods, 'idoverridegroup_add') | Should-BeLessThan ([array]::IndexOf($methods, 'idview_apply'))
            $zoe = ($script:Calls | Where-Object { $_.Method -eq 'idoverrideuser_add' -and $_.Arguments[1] -eq 'zmueller' })
            $zoe.Arguments[0] | Should-Be 'zz-test-legacy-view'
            $zoe.Options.uid | Should-Be 'zmueller-legacy'
            $zoe.Options.uidnumber | Should-Be 5001
            $zoe.Options.loginshell | Should-Be '/bin/bash'
            $zoe.Options.homedirectory | Should-Be '/export/home/zmueller'
            $jose = ($script:Calls | Where-Object { $_.Method -eq 'idoverrideuser_add' -and $_.Arguments[1] -eq 'jnino' })
            @($jose.Options.Keys) | Should-BeCollection @('loginshell')
            $group = ($script:Calls | Where-Object { $_.Method -eq 'idoverridegroup_add' })
            $group.Arguments[1] | Should-Be 'zz-test-dept-engineering'
            $group.Options.cn | Should-Be 'engineering-legacy'
            $group.Options.gidnumber | Should-Be 5100
            ($script:Calls | Where-Object { $_.Method -eq 'idview_apply' }).Options.host | Should-BeCollection @('zz-test-legacy01.ipa.example.com')
        }
    }

    It 'applies the unapplied view to nothing, modifies what exists, and never names the default trust view' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-unapplied-view') }) }
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'idoverrideuser_show') { return [PSCustomObject]@{ result = [PSCustomObject]@{} } }
                [PSCustomObject]@{ result = [PSCustomObject]@{} }
            }
            $r = New-FreeIPAIdView -ViewName unapplied-view -PassThru -Confirm:$false
            $r.UpdatedViews | Should-Be 1
            $r.OverridesUpdated | Should-Be 1
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'idview_apply' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'idoverrideuser_mod' -and $Arguments[1] -eq 'talvarez' -and $IgnoreError -contains 'EmptyModlist' }
            @($script:Calls | Where-Object { @($_.Arguments) -contains 'Default Trust View' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAIdView -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAOtpToken' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                [PSCustomObject]@{ result = [PSCustomObject]@{ ipatokenuniqueid = @($Arguments[0]); ipatokenotpkey = 'SECRET-KEY-MATERIAL'; uri = 'otpauth://totp/x?secret=SECRET-KEY-MATERIAL' } }
            }
        }
    }

    It 'enrols each token on its owner with the QR code suppressed, and never keeps or returns the secret' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAOtpToken -PassThru -Confirm:$false
            $r.CreatedTokens | Should-Be 4
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'otptoken_add' })
            $adds.Arguments | Should-BeCollection @('zz-test-jnino-phone', 'zz-test-zmueller-key', 'zz-test-talvarez-old', 'zz-test-mbell-expired')
            foreach ($add in $adds) {
                $add.Options.no_qrcode | Should-BeTrue
                $add.Options.description | Should-MatchString '\[ZZ-TEST-seed\]$'
                $add.Options.ContainsKey('ipatokenotpkey') | Should-BeFalse
            }
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-jnino-phone' }).Options.ipatokenowner | Should-Be 'jnino'
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-zmueller-key' }).Options.type | Should-Be 'hotp'
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-zmueller-key' }).Options.ipatokenvendor | Should-Be 'Yubico'
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-talvarez-old' }).Options.ipatokendisabled | Should-BeTrue
            $expired = ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-mbell-expired' }).Options
            $expired.ipatokenotpdigits | Should-Be 8
            (ConvertFrom-FreeIPADateTime -Value $expired.ipatokennotafter) | Should-BeLessThan ([DateTimeOffset]::UtcNow)
            ($r | ConvertTo-Json -Depth 5) | Should-NotMatchString 'SECRET-KEY-MATERIAL'
            ($r.Tokens | Where-Object Key -eq 'mbell-expired').Expired | Should-BeTrue
        }
    }

    It 'modifies only what a token can change on a re-run' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ ipatokenuniqueid = @('zz-test-jnino-phone') }) }
            $r = New-FreeIPAOtpToken -TokenId jnino-phone -PassThru -Confirm:$false
            $r.UpdatedTokens | Should-Be 1
            $mod = ($script:Calls | Where-Object { $_.Method -eq 'otptoken_mod' })
            $mod.Options.ContainsKey('type') | Should-BeFalse
            $mod.Options.ContainsKey('ipatokenotpalgorithm') | Should-BeFalse
            $mod.Options.ipatokendisabled | Should-BeFalse
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'otptoken_add' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAOtpToken -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAAutomemberRule' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject {
                switch ($Type) {
                    'Users' { @(1..120 | ForEach-Object { [PSCustomObject]@{ uid = @("user$_") } }) }
                    'Hosts' { @(1..3 | ForEach-Object { [PSCustomObject]@{ fqdn = @("zz-test-h$_.ipa.example.com") } }) }
                    default { @() }
                }
            }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'automember_add_condition') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                if ($Method -eq 'automember_rebuild') { return [PSCustomObject]@{ summary = 'Automember rebuild task finished' } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments) } }
            }
        }
    }

    It 'creates each rule with its kind, keeps an exclusive regex apart from an inclusive one, and rebuilds only the seeded entries in batches' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAAutomemberRule -PassThru -Confirm:$false
            $r.CreatedRules | Should-Be 5
            $r.ConditionsApplied | Should-Be 5
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'automember_add' })
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-contractors' }).Options.type | Should-Be 'group'
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-workstations' }).Options.type | Should-Be 'hostgroup'
            $empty = ($script:Calls | Where-Object { $_.Method -eq 'automember_add_condition' -and $_.Arguments[0] -eq 'zz-test-empty-hold' }).Options
            $empty.key | Should-Be 'uid'
            $empty.automemberexclusiveregex | Should-BeCollection @('.*')
            $empty.ContainsKey('automemberinclusiveregex') | Should-BeFalse
            $contractors = ($script:Calls | Where-Object { $_.Method -eq 'automember_add_condition' -and $_.Arguments[0] -eq 'zz-test-contractors' }).Options
            $contractors.key | Should-Be 'employeetype'
            $contractors.automemberinclusiveregex | Should-BeCollection @('^Contractor$')

            $rebuilds = @($script:Calls | Where-Object { $_.Method -eq 'automember_rebuild' })
            $rebuilds.Count | Should-Be 3
            @($rebuilds | Where-Object { $_.Options.type -eq 'group' } | ForEach-Object { $_.Options.users.Count }) | Should-BeCollection @(100, 20)
            ($rebuilds | Where-Object { $_.Options.type -eq 'hostgroup' }).Options.hosts.Count | Should-Be 3
            foreach ($rebuild in $rebuilds) { ($rebuild.Options.ContainsKey('users') -or $rebuild.Options.ContainsKey('hosts')) | Should-BeTrue }
            $r.EntriesRebuilt | Should-Be 123
        }
    }

    It 'skips the rebuild when told, and never reads or sets the default group' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAAutomemberRule -SkipRebuild -Confirm:$false
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'automember_rebuild' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like 'automember_default_group*' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAAutomemberRule -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAAutomount' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_show') { return $null }
                [PSCustomObject]@{ result = [PSCustomObject]@{} }
            }
        }
    }

    It 'creates the location, the maps and the keys, with the NFS host under the realm domain and the session prefix' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAAutomount -PassThru -Confirm:$false
            $r.LocationsCreated | Should-Be 1
            $r.MapsCreated | Should-Be 2
            $r.KeysCreated | Should-Be 3
            ($script:Calls | Where-Object { $_.Method -eq 'automountlocation_add' }).Arguments | Should-BeCollection @('zz-test-lab')
            $homeMap = ($script:Calls | Where-Object { $_.Method -eq 'automountmap_add_indirect' -and $_.Arguments[1] -eq 'auto.home' })
            $homeMap.Arguments[0] | Should-Be 'zz-test-lab'
            # The API names the mount point 'key'; 'mount' is the CLI's word and is refused.
            $homeMap.Options.key | Should-Be '/home'
            $homeMap.Options.ContainsKey('mount') | Should-BeFalse
            $keys = @($script:Calls | Where-Object { $_.Method -eq 'automountkey_add' })
            @($keys | ForEach-Object { $_.Arguments[1] }) | Should-BeCollection @('auto.home', 'auto.data', 'auto.direct')
            ($keys | Where-Object { $_.Arguments[1] -eq 'auto.home' }).Options.automountkey | Should-Be '*'
            ($keys | Where-Object { $_.Arguments[1] -eq 'auto.home' }).Options.automountinformation | Should-Be '-fstype=nfs4,rw zz-test-nfs01.ipa.example.com:/export/home/&'
            @($keys | Where-Object { $_.Options.automountinformation -match 'ipalab|\{prefix\}' }) | Should-BeCollection -Count 0
            # auto.direct is never created: FreeIPA made it with the location.
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like 'automountmap_add*' -and $Arguments[1] -eq 'auto.direct' }
            @($script:Calls | Where-Object { @($_.Arguments) -contains 'default' }) | Should-BeCollection -Count 0
        }
    }

    It 'modifies what exists on a re-run and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-lab') }) }
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_show') { return [PSCustomObject]@{ result = [PSCustomObject]@{} } }
                [PSCustomObject]@{ result = [PSCustomObject]@{} }
            }
            $r = New-FreeIPAAutomount -PassThru -Confirm:$false
            $r.LocationsCreated | Should-Be 0
            $r.MapsUpdated | Should-Be 2
            $r.KeysUpdated | Should-Be 3
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like '*_add*' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAAutomount -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPASelinuxUserMap' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_add_*') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'scopes a map by its HBAC rule with no members, or by members with no rule, and disables the disabled one' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPASelinuxUserMap -PassThru -Confirm:$false
            $r.CreatedMaps | Should-Be 3
            $staff = ($script:Calls | Where-Object { $_.Method -eq 'selinuxusermap_add' -and $_.Arguments[0] -eq 'zz-test-engineering-staff' }).Options
            $staff.seealso | Should-Be 'zz-test-engineering-ssh'
            $staff.ipaselinuxuser | Should-Be 'staff_u:s0-s0:c0.c1023'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like 'selinuxusermap_add_*' -and $Arguments[0] -eq 'zz-test-engineering-staff' }
            $guest = ($script:Calls | Where-Object { $_.Method -eq 'selinuxusermap_add' -and $_.Arguments[0] -eq 'zz-test-contractors-guest' }).Options
            $guest.ContainsKey('seealso') | Should-BeFalse
            ($script:Calls | Where-Object { $_.Method -eq 'selinuxusermap_add_user' -and $_.Arguments[0] -eq 'zz-test-contractors-guest' }).Options.group | Should-BeCollection @('zz-test-contractors')
            ($script:Calls | Where-Object { $_.Method -eq 'selinuxusermap_add_host' -and $_.Arguments[0] -eq 'zz-test-contractors-guest' }).Options.host | Should-BeCollection @('zz-test-kiosk01.ipa.example.com')
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'selinuxusermap_disable' -and $Arguments[0] -eq 'zz-test-legacy-unconfined' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPASelinuxUserMap -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPACertMapRule' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates the three rules with the domain and the realm escaped into the match rules, and disables the disabled one' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPACertMapRule -PassThru -Confirm:$false
            $r.CreatedRules | Should-Be 3
            $realm = ($script:Calls | Where-Object { $_.Method -eq 'certmaprule_add' -and $_.Arguments[0] -eq 'zz-test-realm-ca' }).Options
            $realm.ipacertmapmatchrule | Should-Be '<ISSUER>CN=Certificate Authority,O=IPA\.EXAMPLE\.COM'
            $realm.ipacertmapmaprule | Should-Be '(userCertificate;binary={cert!bin})'
            $realm.ipacertmappriority | Should-Be 5
            $smartcard = ($script:Calls | Where-Object { $_.Method -eq 'certmaprule_add' -and $_.Arguments[0] -eq 'zz-test-lab-smartcard' }).Options
            $smartcard.ipacertmapmatchrule | Should-Be '<ISSUER>CN=Lab Issuing CA,O=IPALAB'
            $smartcard.ipacertmapmaprule | Should-MatchString '^\(ipacertmapdata='
            $smartcard.ipacertmappriority | Should-Be 10
            $email = ($script:Calls | Where-Object { $_.Method -eq 'certmaprule_add' -and $_.Arguments[0] -eq 'zz-test-legacy-email-match' }).Options
            $email.ipacertmapmatchrule | Should-Be '<SAN:rfc822Name>.*@ipa\.example\.com'
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'certmaprule_disable' -and $Arguments[0] -eq 'zz-test-legacy-email-match' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'certmaprule_disable' -and $Arguments[0] -eq 'zz-test-lab-smartcard' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPACertMapRule -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}
