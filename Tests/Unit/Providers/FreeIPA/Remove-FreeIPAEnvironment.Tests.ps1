#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown is the destructive half of the module, and the property that matters most is
    that -WhatIf wins over -Force: -Force defeating -WhatIf was the worst defect an earlier
    module shipped, and it is pinned here first. After that, the order - hosts before host
    groups, users in every state before the groups that held them, leaf groups before their
    parents - the batching that keeps a run of four hundred hosts from being four hundred
    round trips while every object is still confirmed by name, that DNS is never updated by
    a host delete, that a failure the server reports inside a batch is recorded against its
    name, and the promise that the service account is left alone unless asked for, and
    removed last when it is.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-FreeIPAEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; AuthType = 'Credential'; CredentialPath = $null } }
            Mock Write-TestMessage { }
            Mock Write-Host { }

            Mock Get-FreeIPASeededObject {
                switch ($Type) {
                    'Users' {
                        $list = @([PSCustomObject]@{ uid = @('awhitfield') }, [PSCustomObject]@{ uid = @('talvarez') })
                        if ($IncludeServiceAccount) { $list += [PSCustomObject]@{ uid = @('zz-test-automation') } }
                        return $list
                    }
                    'PreservedUsers' { @([PSCustomObject]@{ uid = @('rokafor') }) }
                    'StagedUsers' { @([PSCustomObject]@{ uid = @('lchen') }) }
                    'Groups' {
                        @(
                            [PSCustomObject]@{ cn = @('zz-test-all-staff'); memberof_group = @() }
                            [PSCustomObject]@{ cn = @('zz-test-team-platform'); memberof_group = @('zz-test-dept-engineering') }
                            [PSCustomObject]@{ cn = @('zz-test-dept-engineering'); memberof_group = @('zz-test-all-staff') }
                        )
                    }
                    'Hostgroups' { @([PSCustomObject]@{ cn = @('zz-test-web-servers') }, [PSCustomObject]@{ cn = @('zz-test-all-servers') }) }
                    'Hosts' { @([PSCustomObject]@{ fqdn = @('zz-test-web01.ipa.example.com') }, [PSCustomObject]@{ fqdn = @('zz-test-db01.ipa.example.com') }) }
                }
            }

            $script:Deleted = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Deleted.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                [PSCustomObject]@{ result = [PSCustomObject]@{ failed = @() }; value = @($Arguments) }
            }
        }
    }

    It 'deletes nothing under -WhatIf, even with -Force' {
        InModuleScope TestEnvironment {
            $r = Remove-FreeIPAEnvironment -WhatIf -Force -PassThru
            Should-NotInvoke Invoke-FreeIPARequest
            (@('Hosts', 'Hostgroups', 'Users', 'Groups') | ForEach-Object { @($r.$_.Removed).Count } | Measure-Object -Sum).Sum | Should-Be 0
        }
    }

    It 'removes hosts, then host groups, then users in every state, then groups deepest first, in batches' {
        InModuleScope TestEnvironment {
            $r = Remove-FreeIPAEnvironment -Force -PassThru

            $methods = @($script:Deleted | ForEach-Object { $_.Method })
            $methods | Should-BeCollection @('host_del', 'hostgroup_del', 'user_del', 'user_del', 'stageuser_del', 'group_del')
            $script:Deleted[0].Arguments | Should-BeCollection @('zz-test-web01.ipa.example.com', 'zz-test-db01.ipa.example.com')
            $script:Deleted[0].Options.updatedns | Should-BeFalse
            $script:Deleted[0].Options.continue | Should-BeTrue
            $script:Deleted[2].Arguments | Should-BeCollection @('awhitfield', 'talvarez')
            $script:Deleted[3].Arguments | Should-BeCollection @('rokafor')
            $script:Deleted[4].Arguments | Should-BeCollection @('lchen')
            $script:Deleted[5].Arguments | Should-BeCollection @('zz-test-team-platform', 'zz-test-dept-engineering', 'zz-test-all-staff')
            @($r.Users.Removed).Count | Should-Be 4
            @($r.Groups.Removed).Count | Should-Be 3
        }
    }

    It 'removes the access layers before the directory, each in the reverse of the order it was built' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject {
                switch ($Type) {
                    'ServiceDelegationRules' { @([PSCustomObject]@{ cn = @('zz-test-web-to-ldap') }) }
                    'ServiceDelegationTargets' { @([PSCustomObject]@{ cn = @('zz-test-ldap-targets') }) }
                    'Services' { @([PSCustomObject]@{ krbcanonicalname = @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM') }) }
                    'PasswordPolicies' { @([PSCustomObject]@{ cn = @('zz-test-dept-sales') }) }
                    'Roles' { @([PSCustomObject]@{ cn = @('zz-test-lab-helpdesk') }) }
                    'Privileges' { @([PSCustomObject]@{ cn = @('zz-test-lab-password-reset') }) }
                    'Permissions' { @([PSCustomObject]@{ cn = @('zz-test-reset-lab-passwords') }) }
                    'SudoRules' { @([PSCustomObject]@{ cn = @('zz-test-dba-postgres') }) }
                    'SudoCommandGroups' { @([PSCustomObject]@{ cn = @('zz-test-editors') }) }
                    'SudoCommands' { @([PSCustomObject]@{ sudocmd = @('/usr/bin/vim') }) }
                    'HbacRules' { @([PSCustomObject]@{ cn = @('zz-test-staff-bastion') }) }
                    'HbacServiceGroups' { @([PSCustomObject]@{ cn = @('zz-test-remote-access') }) }
                    'HbacServices' { @([PSCustomObject]@{ cn = @('zz-test-payroll') }) }
                    'Netgroups' { @([PSCustomObject]@{ cn = @('zz-test-eng-nfs') }) }
                    'Hosts' { @([PSCustomObject]@{ fqdn = @('zz-test-web01.ipa.example.com') }) }
                    default { @() }
                }
            }

            $r = Remove-FreeIPAEnvironment -Force -PassThru

            $methods = @($script:Deleted | ForEach-Object { $_.Method })
            $methods | Should-BeCollection @('servicedelegationrule_del', 'servicedelegationtarget_del', 'service_del', 'pwpolicy_del', 'role_del', 'privilege_del', 'permission_del', 'sudorule_del', 'sudocmdgroup_del', 'sudocmd_del', 'hbacrule_del', 'hbacsvcgroup_del', 'hbacsvc_del', 'netgroup_del', 'host_del')
            ($script:Deleted | Where-Object { $_.Method -eq 'service_del' }).Arguments | Should-BeCollection @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM')
            ($script:Deleted | Where-Object { $_.Method -eq 'sudocmd_del' }).Arguments | Should-BeCollection @('/usr/bin/vim')
            @($r.Services.Removed).Count | Should-Be 3
            @($r.Roles.Removed).Count | Should-Be 3
            @($r.SudoRules.Removed).Count | Should-Be 3
            @($r.HbacRules.Removed).Count | Should-Be 3
        }
    }

    It 'never names the service account unless asked, and removes it last when asked' {
        InModuleScope TestEnvironment {
            $null = Remove-FreeIPAEnvironment -Force
            @($script:Deleted | ForEach-Object { $_.Arguments } | Where-Object { $_ -eq 'zz-test-automation' }).Count | Should-Be 0

            $script:Deleted.Clear()
            $r = Remove-FreeIPAEnvironment -Force -RemoveServiceAccount -PassThru
            $script:Deleted[-1].Method | Should-Be 'user_del'
            $script:Deleted[-1].Arguments | Should-BeCollection @('zz-test-automation')
            $r.ServiceAccount.Removed | Should-BeCollection @('zz-test-automation')
        }
    }

    It 'keeps what it is told to keep' {
        InModuleScope TestEnvironment {
            $null = Remove-FreeIPAEnvironment -Force -Keep Users, Groups
            $methods = @($script:Deleted | ForEach-Object { $_.Method })
            $methods | Should-BeCollection @('host_del', 'hostgroup_del')
        }
    }

    It 'confirms every object by name and sends the confirmed ones in batches of fifty' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject {
                if ($Type -eq 'Hosts') { return @(1..120 | ForEach-Object { [PSCustomObject]@{ fqdn = @("zz-test-h$_.ipa.example.com") } }) }
                @()
            }
            $r = Remove-FreeIPAEnvironment -Force -Keep Users, Groups, Hostgroups -PassThru
            $batches = @($script:Deleted | Where-Object { $_.Method -eq 'host_del' })
            $batches.Count | Should-Be 3
            @($batches | ForEach-Object { $_.Arguments.Count }) | Should-BeCollection @(50, 50, 20)
            @($r.Hosts.Removed).Count | Should-Be 120
        }
    }

    It 'records a failure the server reports inside a batch against its name, and counts the rest as removed' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                [PSCustomObject]@{ result = [PSCustomObject]@{ failed = @('zz-test-db01.ipa.example.com: no such entry') }; value = @() }
            }
            $r = Remove-FreeIPAEnvironment -Force -Keep Users, Groups, Hostgroups -PassThru -ErrorAction SilentlyContinue
            $r.Hosts.Removed | Should-BeCollection @('zz-test-web01.ipa.example.com')
            @($r.Hosts.Errors).Count | Should-Be 1
            $r.Hosts.Errors[0] | Should-MatchString 'db01'
        }
    }

    It 'removes the credential record and its vault secret only under both switches, reading the pointer first' {
        InModuleScope TestEnvironment {
            $record = Join-Path $TestDrive 'ipa.example.com.freeipa.json'
            [System.IO.File]::WriteAllText($record, '{"baseUrl":"https://ipa.example.com","username":"zz-test-automation","protection":"SecretStore","vaultName":"FreeIPAEnvironment","secretName":"FreeIPAEnvironment-ipa.example.com-zz-test-automation"}')
            Mock Get-FreeIPACredentialPath { $record }
            Mock Remove-TestVaultSecret { }

            $null = Remove-FreeIPAEnvironment -Force -RemoveServiceAccount
            Test-Path $record | Should-BeTrue
            Should-NotInvoke Remove-TestVaultSecret

            $r = Remove-FreeIPAEnvironment -Force -RemoveServiceAccount -RemoveCredentialFile -PassThru
            Test-Path $record | Should-BeFalse
            Should-Invoke Remove-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $SecretName -eq 'FreeIPAEnvironment-ipa.example.com-zz-test-automation' }
            $r.ServiceAccount.Removed | Should-ContainCollection $record
        }
    }
}
