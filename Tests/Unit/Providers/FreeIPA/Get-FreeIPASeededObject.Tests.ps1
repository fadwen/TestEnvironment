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
            $script:Connection = @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-' }
            $script:Queries = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Queries.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options; Find = [bool]$Find })
                switch ($Method) {
                    'user_find' {
                        @(
                            [PSCustomObject]@{ uid = @('awhitfield'); userclass = @('ZZ-TEST-seed', 'employee') }
                            [PSCustomObject]@{ uid = @('zz-test-automation'); userclass = @('ZZ-TEST-seed') }
                            [PSCustomObject]@{ uid = @('lookalike'); userclass = @('employee') }
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
                    'host_find' { @([PSCustomObject]@{ fqdn = @('zz-test-web01.ipa.example.com'); userclass = @('ZZ-TEST-seed', 'server') }, [PSCustomObject]@{ fqdn = @('real.ipa.example.com'); userclass = @('ZZ-TEST-seed') }) }
                    'hbacrule_find' { @([PSCustomObject]@{ cn = @('zz-test-staff-bastion'); description = @('x [ZZ-TEST-seed]') }, [PSCustomObject]@{ cn = @('allow_all'); description = @('Allow all users to access any host from any host') }, [PSCustomObject]@{ cn = @('zz-test-admin-made'); description = @('no marker') }) }
                    'sudocmd_find' { @([PSCustomObject]@{ sudocmd = @('/usr/bin/vim'); description = @('Text editor [ZZ-TEST-seed]') }, [PSCustomObject]@{ sudocmd = @('/usr/bin/dnf'); description = @('Existed before the seed') }) }
                    'permission_find' { @([PSCustomObject]@{ cn = @('zz-test-read-lab-hosts') }, [PSCustomObject]@{ cn = @('System: Read Hosts') }) }
                    'pwpolicy_find' { @([PSCustomObject]@{ cn = @('zz-test-all-staff'); cospriority = @(5) }, [PSCustomObject]@{ cn = @('zz-test-lookalike'); cospriority = @(6) }, [PSCustomObject]@{ cn = @('global_policy') }) }
                    'service_find' { @([PSCustomObject]@{ krbcanonicalname = @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM') }, [PSCustomObject]@{ krbcanonicalname = @('HTTP/zz-test-gone.ipa.example.com@IPA.EXAMPLE.COM') }, [PSCustomObject]@{ krbcanonicalname = @('HTTP/ipa.example.com@IPA.EXAMPLE.COM') }) }
                    'servicedelegationrule_find' { @([PSCustomObject]@{ cn = @('zz-test-web-to-ldap') }, [PSCustomObject]@{ cn = @('ipa-http-delegation') }) }
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
            @(Get-FreeIPASeededObject -Type Hosts -Connection $script:Connection).fqdn | Should-BeCollection @('zz-test-web01.ipa.example.com')
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
            @(Get-FreeIPASeededObject -Type Services -Connection $script:Connection).krbcanonicalname | Should-BeCollection @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM')
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
