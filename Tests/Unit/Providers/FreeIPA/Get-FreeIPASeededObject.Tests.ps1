#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Ownership discovery is what teardown deletes by, and the property that matters is that
    every type needs its evidence and not just its name. A group an administrator named with
    our prefix but without the marker is not ours; a user without the tag is not ours
    whatever it is called; the service account is ours but is the credential in use. Each is
    pinned, along with the server-side filters that keep a three-hundred-user realm from
    being read in full to find ten.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreeIPASeededObject' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; Domain = 'ipa.example.com' }
            $script:Queries = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Queries.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options; Find = [bool]$Find })
                switch ($Method) {
                    'user_find' {
                        @(
                            [PSCustomObject]@{ uid = @('awhitfield'); userclass = @('ZZ-TEST-seed', 'employee'); usercertificate = @([PSCustomObject]@{ __base64__ = 'MIIE' }) }
                            [PSCustomObject]@{ uid = @('zz-test-automation'); userclass = @('ZZ-TEST-seed') }
                            [PSCustomObject]@{ uid = @('lookalike'); userclass = @('employee'); usercertificate = @([PSCustomObject]@{ __base64__ = 'MIIE' }) }
                        )
                    }
                    'stageuser_find' { @([PSCustomObject]@{ uid = @('lchen'); userclass = @('ZZ-TEST-seed', 'employee') }) }
                    'group_find' {
                        @(
                            [PSCustomObject]@{ cn = @('zz-test-all-staff'); description = @('Every employee [ZZ-TEST-seed]') }
                            [PSCustomObject]@{ cn = @('zz-test-lookalike'); description = @('Somebody else named it this way') }
                            [PSCustomObject]@{ cn = @('other-zz-test-group'); description = @('Has the marker [ZZ-TEST-seed] but not the prefix') }
                        )
                    }
                    'hostgroup_find' { @([PSCustomObject]@{ cn = @('zz-test-web-servers'); description = @('Web [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('zz-test-nomarker'); description = @('x') }) }
                    'host_find' { @([PSCustomObject]@{ fqdn = @('zz-test-web01.zz-test-lab.ipa.example.com'); userclass = @('ZZ-TEST-seed', 'server'); usercertificate = @([PSCustomObject]@{ __base64__ = 'MIIE' }) }, [PSCustomObject]@{ fqdn = @('real.ipa.example.com'); userclass = @('ZZ-TEST-seed'); usercertificate = @([PSCustomObject]@{ __base64__ = 'MIIE' }) }) }
                    'hbacrule_find' { @([PSCustomObject]@{ cn = @('zz-test-staff-bastion'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('allow_all'); description = @('Allow all users to access any host from any host') }, [PSCustomObject]@{ cn = @('zz-test-admin-made'); description = @('no marker') }) }
                    'sudocmd_find' { @([PSCustomObject]@{ sudocmd = @('/usr/bin/vim'); description = @('Text editor [ZZ-TEST-seed]') }, [PSCustomObject]@{ sudocmd = @('/usr/bin/dnf'); description = @('Existed before the seed') }) }
                    'permission_find' { @([PSCustomObject]@{ cn = @('zz-test-read-lab-hosts') }, [PSCustomObject]@{ cn = @('System: Read Hosts') }) }
                    'pwpolicy_find' { @([PSCustomObject]@{ cn = @('zz-test-all-staff'); cospriority = @(5) }, [PSCustomObject]@{ cn = @('zz-test-lookalike'); cospriority = @(6) }, [PSCustomObject]@{ cn = @('global_policy') }) }
                    'service_find' { @([PSCustomObject]@{ krbcanonicalname = @('HTTP/zz-test-web01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM') }, [PSCustomObject]@{ krbcanonicalname = @('HTTP/zz-test-gone.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM') }, [PSCustomObject]@{ krbcanonicalname = @('HTTP/ipa.example.com@IPA.EXAMPLE.COM') }) }
                    'servicedelegationrule_find' { @([PSCustomObject]@{ cn = @('zz-test-web-to-ldap') }, [PSCustomObject]@{ cn = @('ipa-http-delegation') }) }
                    'otptoken_find' { @([PSCustomObject]@{ ipatokenuniqueid = @('zz-test-jnino-phone'); description = @('Authenticator app [ZZ-TEST-seed]') }, [PSCustomObject]@{ ipatokenuniqueid = @('zz-test-lookalike'); description = @('no marker') }) }
                    'automember_find' { if ($Options.type -eq 'group') { @([PSCustomObject]@{ cn = @('zz-test-contractors'); description = @('x [ZZ-TEST-seed]') }) } else { @([PSCustomObject]@{ cn = @('zz-test-workstations'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('zz-test-nomarker'); description = @('x') }) } }
                    'automountlocation_find' { @([PSCustomObject]@{ cn = @('zz-test-lab') }, [PSCustomObject]@{ cn = @('default') }) }
                    'idview_find' { @([PSCustomObject]@{ cn = @('zz-test-legacy-view'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('Default Trust View'); description = @('Default Trust View for AD users') }) }
                    'dnszone_find' {
                        $z = { param($name, $contact) [PSCustomObject]@{ idnsname = @([PSCustomObject]@{ __dns_name__ = $name }); idnssoarname = @([PSCustomObject]@{ __dns_name__ = $contact }) } }
                        # The server filters on the contact, so only matching zones come back;
                        # a lookalike with the seed's contact on another name is still refused.
                        @((& $z 'zz-test-lab.ipa.example.com.' 'hostmaster.zz-test-lab.ipa.example.com.'), (& $z '213.10.in-addr.arpa.' 'hostmaster.zz-test-lab.ipa.example.com.'), (& $z 'zz-test-other.ipa.example.com.' 'hostmaster.zz-test-lab.ipa.example.com.'))
                    }
                    'dnsrecord_find' {
                        if ($Arguments[0] -like '213.*') { @([PSCustomObject]@{ idnsname = @([PSCustomObject]@{ __dns_name__ = '11.0' }); ptrrecord = @('zz-test-web01.zz-test-lab.ipa.example.com.') }) }
                        else { @([PSCustomObject]@{ idnsname = @([PSCustomObject]@{ __dns_name__ = '@' }); nsrecord = @('ipa.example.com.') }, [PSCustomObject]@{ idnsname = @([PSCustomObject]@{ __dns_name__ = 'zz-test-web01' }); arecord = @('10.213.0.11') }) }
                    }
                    'radiusproxy_find' { @([PSCustomObject]@{ cn = @('zz-test-legacy-radius'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('zz-test-nomarker'); description = @('x') }) }
                    'idp_find' { @([PSCustomObject]@{ cn = @('zz-test-github') }, [PSCustomObject]@{ cn = @('corp-okta') }) }
                    'caacl_find' { @([PSCustomObject]@{ cn = @('zz-test-user-certs'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('hosts_services_caIPAserviceCert'); description = @('') }, [PSCustomObject]@{ cn = @('zz-test-nomarker'); description = @('x') }) }
                    'cert_find' {
                        if ($Options.ContainsKey('user')) { @([PSCustomObject]@{ serial_number = '11'; status = 'VALID'; owner_user = @('awhitfield') }, [PSCustomObject]@{ serial_number = '12'; status = 'REVOKED'; owner_user = @('awhitfield') }) }
                        elseif ($Options.ContainsKey('host')) { @([PSCustomObject]@{ serial_number = '13'; status = 'VALID'; owner_host = @('zz-test-web01.zz-test-lab.ipa.example.com') }) }
                        else { @() }
                    }
                    default { @() }
                }
            }
        }
    }

    It 'finds users by the tag server-side and excludes the service account unless asked' {
        InModuleScope TestEnvironment {
            $users = @(Get-FreeIPASeededObject -Type Users -Connection $script:Connection)
            $users.uid | Should-BeCollection @('awhitfield')
            $script:Queries[0].Options.userclass | Should-Be 'ZZ-TEST-seed'
            $script:Queries[0].Find | Should-BeTrue
            $script:Queries[0].Options.ContainsKey('preserved') | Should-BeFalse

            $withService = @(Get-FreeIPASeededObject -Type Users -IncludeServiceAccount -Connection $script:Connection)
            $withService.Count | Should-Be 2
        }
    }

    It 'asks for preserved and staged users separately' {
        InModuleScope TestEnvironment {
            $null = @(Get-FreeIPASeededObject -Type PreservedUsers -Connection $script:Connection)
            $script:Queries[0].Method | Should-Be 'user_find'
            $script:Queries[0].Options.preserved | Should-BeTrue
            $script:Queries[0].Options.userclass | Should-Be 'ZZ-TEST-seed'

            $staged = @(Get-FreeIPASeededObject -Type StagedUsers -Connection $script:Connection)
            $staged.uid | Should-BeCollection @('lchen')
            $script:Queries[1].Method | Should-Be 'stageuser_find'
        }
    }

    It 'requires both the prefix and the marker on a group, and on a host group' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type Groups -Connection $script:Connection).cn | Should-BeCollection @('zz-test-all-staff')
            $script:Queries[0].Arguments | Should-BeCollection @('zz-test-')
            @(Get-FreeIPASeededObject -Type Hostgroups -Connection $script:Connection).cn | Should-BeCollection @('zz-test-web-servers')
        }
    }

    It 'requires both the tag and the prefix on a host' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type Hosts -Connection $script:Connection).fqdn | Should-BeCollection @('zz-test-web01.zz-test-lab.ipa.example.com')
            $script:Queries[0].Options.userclass | Should-Be 'ZZ-TEST-seed'
        }
    }

    It 'never claims a stock rule, an unmarked lookalike, or a command that existed before the seed' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type HbacRules -Connection $script:Connection).cn | Should-BeCollection @('zz-test-staff-bastion')
            @(Get-FreeIPASeededObject -Type SudoCommands -Connection $script:Connection).sudocmd | Should-BeCollection @('/usr/bin/vim')
            # A command is searched by the marker, since its name is a path.
            $script:Queries[-1].Arguments | Should-BeCollection @('[ZZ-TEST-seed]')
            @(Get-FreeIPASeededObject -Type Permissions -Connection $script:Connection).cn | Should-BeCollection @('zz-test-read-lab-hosts')
            @(Get-FreeIPASeededObject -Type ServiceDelegationRules -Connection $script:Connection).cn | Should-BeCollection @('zz-test-web-to-ldap')
        }
    }

    It 'claims a password policy only when its group is seeded, and a service only on a seeded host' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type PasswordPolicies -Connection $script:Connection).cn | Should-BeCollection @('zz-test-all-staff')
            @(Get-FreeIPASeededObject -Type Services -Connection $script:Connection).krbcanonicalname | Should-BeCollection @('HTTP/zz-test-web01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM')
        }
    }

    It 'finds the identity detail by prefix and marker, tags automember rules with their kind, and never the default view or location' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type OtpTokens -Connection $script:Connection).ipatokenuniqueid | Should-BeCollection @('zz-test-jnino-phone')
            $rules = @(Get-FreeIPASeededObject -Type AutomemberRules -Connection $script:Connection)
            @($rules | ForEach-Object { '{0}/{1}' -f $_.automembertype, $_.cn[0] }) | Should-BeCollection @('group/zz-test-contractors', 'hostgroup/zz-test-workstations')
            # automember_find refuses the limits every other search takes.
            @($script:Queries | Where-Object { $_.Method -eq 'automember_find' } | ForEach-Object { $_.Options.ContainsKey('timelimit') }) | Should-BeCollection @($false, $false)
            @(Get-FreeIPASeededObject -Type AutomountLocations -Connection $script:Connection).cn | Should-BeCollection @('zz-test-lab')
            @(Get-FreeIPASeededObject -Type IdViews -Connection $script:Connection).cn | Should-BeCollection @('zz-test-legacy-view')
        }
    }

    It 'proves a certificate by its owner, asking the CA one seeded holder at a time with the full record' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type CaAcls -Connection $script:Connection).cn | Should-BeCollection @('zz-test-user-certs')

            $certs = @(Get-FreeIPASeededObject -Type Certificates -Connection $script:Connection)
            @($certs | ForEach-Object { '{0}/{1}' -f $_.ownerkind, $_.serial_number }) | Should-BeCollection @('user/11', 'user/12', 'host/13')
            $finds = @($script:Queries | Where-Object { $_.Method -eq 'cert_find' })
            # One call per seeded entry that carries a certificate, never two owners in one
            # call (the CA would answer with what both hold), and never for an entry
            # without one: the service account, the lookalike user, the real host and the
            # service are not asked about.
            $finds.Count | Should-Be 2
            @($finds | ForEach-Object { @($_.Options.user) + @($_.Options.host) + @($_.Options.service) | Where-Object { $_ } }) | Should-BeCollection @('awhitfield', 'zz-test-web01.zz-test-lab.ipa.example.com')
            foreach ($find in $finds) {
                $find.Options.all | Should-BeTrue
                $find.Find | Should-BeTrue
                (@($find.Options.user) + @($find.Options.host) + @($find.Options.service) | Where-Object { $_ }).Count | Should-Be 1
            }
            # The holders are read from the full listings, so each is asked for once.
            @($script:Queries | Where-Object { $_.Method -in 'user_find', 'host_find', 'service_find' -and $_.Options.all }).Count | Should-Be 3
        }
    }

    It 'proves a zone by the seed contact and one of the two derived names, and reads records per seeded zone' {
        InModuleScope TestEnvironment {
            $zones = @(Get-FreeIPASeededObject -Type DnsZones -Connection $script:Connection)
            @($zones | ForEach-Object { '{0}/{1}' -f $_.zonekind, $_.idnsname[0].__dns_name__ }) | Should-BeCollection @('Forward/zz-test-lab.ipa.example.com.', 'Reverse/213.10.in-addr.arpa.')
            $script:Queries[0].Method | Should-Be 'dnszone_find'
            $script:Queries[0].Options.idnssoarname | Should-Be 'hostmaster.zz-test-lab.ipa.example.com.'

            $records = @(Get-FreeIPASeededObject -Type DnsRecords -Connection $script:Connection)
            @($records | ForEach-Object { '{0} {1}' -f $_.zonename, $_.idnsname[0].__dns_name__ }) | Should-BeCollection @('zz-test-lab.ipa.example.com. @', 'zz-test-lab.ipa.example.com. zz-test-web01', '213.10.in-addr.arpa. 11.0')
            @($script:Queries | Where-Object { $_.Method -eq 'dnsrecord_find' } | ForEach-Object { $_.Arguments[0] }) | Should-BeCollection @('zz-test-lab.ipa.example.com.', '213.10.in-addr.arpa.')
        }
    }

    It 'requires the marker on a proxy and, since a provider has no description, the prefix alone on one' {
        InModuleScope TestEnvironment {
            @(Get-FreeIPASeededObject -Type RadiusProxies -Connection $script:Connection).cn | Should-BeCollection @('zz-test-legacy-radius')
            @(Get-FreeIPASeededObject -Type IdentityProviders -Connection $script:Connection).cn | Should-BeCollection @('zz-test-github')
        }
    }

    It 'asks for every attribute only under -Detail' {
        InModuleScope TestEnvironment {
            $null = @(Get-FreeIPASeededObject -Type Groups -Connection $script:Connection)
            $script:Queries[0].Options.ContainsKey('all') | Should-BeFalse
            $null = @(Get-FreeIPASeededObject -Type Groups -Detail -Connection $script:Connection)
            $script:Queries[1].Options.all | Should-BeTrue
        }
    }
}
