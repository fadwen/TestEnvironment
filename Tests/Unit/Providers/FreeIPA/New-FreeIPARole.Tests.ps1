#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The delegation chain and the policies and services that sit beside it. Pinned for RBAC:
    permissions before privileges before roles, the write permission's filter carrying the
    tag substituted for its placeholder, a stock privilege named through builtin: sent by its
    own name and never created, and a host as a role member. For password policies: one per
    seeded group with the API's attribute names, and never the global policy. For services:
    the principal under the realm's domain, forced because the host has no DNS entry, the
    authentication indicator, managed-by through the host, and delegation targets before the
    rules that name them with realm-qualified principals.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPARole' -Tag 'Unit', 'Public', 'Safety' {

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

    It 'builds the chain from the bottom, with the tag substituted into the write permission''s filter' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPARole -PassThru -Confirm:$false
            $r.PermissionsCreated | Should-Be 3
            $r.PrivilegesCreated | Should-Be 3
            $r.CreatedRoles | Should-Be 4
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'permission_add') | Should-BeLessThan ([array]::IndexOf($methods, 'privilege_add'))
            [array]::LastIndexOf($methods, 'privilege_add') | Should-BeLessThan ([array]::IndexOf($methods, 'role_add'))
            $write = ($script:Calls | Where-Object { $_.Method -eq 'permission_add' -and $_.Arguments[0] -eq 'zz-test-reset-lab-passwords' }).Options
            $write.ipapermright | Should-BeCollection @('write')
            $write.type | Should-Be 'user'
            $write.extratargetfilter | Should-BeCollection @('(userclass=ZZ-TEST-seed)')
            $read = ($script:Calls | Where-Object { $_.Method -eq 'permission_add' -and $_.Arguments[0] -eq 'zz-test-read-lab-sudo' }).Options
            $read.ContainsKey('extratargetfilter') | Should-BeFalse
            $read.ContainsKey('attrs') | Should-BeFalse
        }
    }

    It 'names a stock privilege by its own name inside a role and never creates or modifies it' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPARole -RoleName lab-helpdesk -Confirm:$false
            ($script:Calls | Where-Object { $_.Method -eq 'role_add_privilege' }).Options.privilege | Should-BeCollection @('zz-test-lab-password-reset', 'Password Policy Readers')
            @($script:Calls | Where-Object { $_.Method -like 'privilege_*' -and $_.Arguments[0] -eq 'Password Policy Readers' }) | Should-BeCollection -Count 0
            ($script:Calls | Where-Object { $_.Method -eq 'role_add_member' }).Options.group | Should-BeCollection @('zz-test-lab-admins')
        }
    }

    It 'adds a host as a role member, and gives the empty role its privilege and nobody' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPARole -RoleName lab-host-self, empty-role -Confirm:$false
            ($script:Calls | Where-Object { $_.Method -eq 'role_add_member' -and $_.Arguments[0] -eq 'zz-test-lab-host-self' }).Options.host | Should-BeCollection @('zz-test-web01.ipa.example.com')
            @($script:Calls | Where-Object { $_.Method -eq 'role_add_member' -and $_.Arguments[0] -eq 'zz-test-empty-role' }) | Should-BeCollection -Count 0
            ($script:Calls | Where-Object { $_.Method -eq 'role_add_privilege' -and $_.Arguments[0] -eq 'zz-test-empty-role' }).Options.privilege | Should-BeCollection @('zz-test-lab-sudo-auditors')
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPARole -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAPasswordPolicy' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates one policy per seeded group with the API''s attribute names, and never names the global policy' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAPasswordPolicy -PassThru -Confirm:$false
            $r.CreatedPolicies | Should-Be 3
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'pwpolicy_add' })
            $adds.Arguments | Should-BeCollection @('zz-test-lab-admins', 'zz-test-contractors', 'zz-test-dept-sales')
            $sales = ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-dept-sales' }).Options
            $sales.cospriority | Should-Be 200
            $sales.krbmaxpwdlife | Should-Be 0
            $sales.passwordgracelimit | Should-Be -1
            $admins = ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-lab-admins' }).Options
            $admins.krbpwdminlength | Should-Be 20
            $admins.krbpwdmindiffchars | Should-Be 4
            $admins.krbpwdlockoutduration | Should-Be 1800
            @($script:Calls | Where-Object { @($_.Arguments) -contains 'global_policy' }) | Should-BeCollection -Count 0
        }
    }

    It 'modifies a policy that exists' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-contractors') }) }
            $r = New-FreeIPAPasswordPolicy -GroupName contractors -PassThru -Confirm:$false
            $r.UpdatedPolicies | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'pwpolicy_mod' -and $IgnoreError -contains 'EmptyModlist' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'pwpolicy_add' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAPasswordPolicy -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAService' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like '*_add_*') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ krbcanonicalname = @($Arguments[0]) } }
            }
        }
    }

    It 'creates each service on its seeded host with force, an indicator where the row has one, and managed-by through the host' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAService -PassThru -Confirm:$false
            $r.CreatedServices | Should-Be 4
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'service_add' })
            $adds.Arguments | Should-BeCollection @('HTTP/zz-test-web01.ipa.example.com', 'postgres/zz-test-db01.ipa.example.com', 'ldap/zz-test-legacy01.ipa.example.com', 'HTTP/zz-test-bastion01.ipa.example.com')
            foreach ($add in $adds) { $add.Options.force | Should-BeTrue }
            ($adds | Where-Object { $_.Arguments[0] -like 'HTTP/zz-test-bastion01*' }).Options.krbprincipalauthind | Should-BeCollection @('otp')
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'service_add_host' -and $Arguments[0] -eq 'postgres/zz-test-db01.ipa.example.com' -and $Options.host -contains 'zz-test-web01.ipa.example.com' }
            @($script:Calls | Where-Object { $_.Method -like '*keytab*' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates delegation targets before the rules that name them, with realm-qualified principals' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAService -PassThru -Confirm:$false
            $r.DelegationTargetsCreated | Should-Be 2
            $r.DelegationRulesCreated | Should-Be 1
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'servicedelegationtarget_add') | Should-BeLessThan ([array]::IndexOf($methods, 'servicedelegationrule_add'))
            ($script:Calls | Where-Object { $_.Method -eq 'servicedelegationtarget_add_member' -and $_.Arguments[0] -eq 'zz-test-ldap-targets' }).Options.principal | Should-BeCollection @('ldap/zz-test-legacy01.ipa.example.com@IPA.EXAMPLE.COM')
            ($script:Calls | Where-Object { $_.Method -eq 'servicedelegationrule_add_member' }).Options.principal | Should-BeCollection @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM')
            ($script:Calls | Where-Object { $_.Method -eq 'servicedelegationrule_add_target' }).Options.servicedelegationtarget | Should-BeCollection @('zz-test-ldap-targets')
            @($script:Calls | Where-Object { $_.Method -eq 'servicedelegationtarget_add_member' -and $_.Arguments[0] -eq 'zz-test-empty-target' }) | Should-BeCollection -Count 0
            @($script:Calls | Where-Object { @($_.Arguments) -like 'ipa-*-delegation*' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAService -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPANetgroup' -Tag 'Unit', 'Public' {

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

    It 'creates every netgroup before adding members, so a nested netgroup exists when it is named' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPANetgroup -PassThru -Confirm:$false
            $r.CreatedNetgroups | Should-Be 4
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'netgroup_add') | Should-BeLessThan ([array]::IndexOf($methods, 'netgroup_add_member'))
            $nfs = ($script:Calls | Where-Object { $_.Method -eq 'netgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-eng-nfs' }).Options
            $nfs.group | Should-BeCollection @('zz-test-dept-engineering')
            $nfs.hostgroup | Should-BeCollection @('zz-test-web-servers', 'zz-test-db-servers')
            $nfs.ContainsKey('user') | Should-BeFalse
            $all = ($script:Calls | Where-Object { $_.Method -eq 'netgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-lab-all' }).Options
            $all.netgroup | Should-BeCollection @('zz-test-eng-nfs', 'zz-test-zurich')
            ($script:Calls | Where-Object { $_.Method -eq 'netgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-zurich' }).Options.host | Should-BeCollection @('zz-test-kiosk01.ipa.example.com')
            @($script:Calls | Where-Object { $_.Method -eq 'netgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-empty-net' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPANetgroup -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}
