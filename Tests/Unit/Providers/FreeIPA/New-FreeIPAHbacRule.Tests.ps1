#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    HBAC is what decides who may log in where on every enrolled host, and the safety property
    is that the seed never touches a rule the realm shipped with: allow_all,
    allow_systemd-user or anything else without the prefix is never created, modified,
    enabled or disabled, and there is no switch to change that. Beyond the property: services
    and service groups before the rules that name them, a stock service referenced through
    builtin: sent by its own name and never created, the who/where/what added after the rule
    exists, a category of all carrying no members of that kind, and the disabled rule
    disabled after creation.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAHbacRule' -Tag 'Unit', 'Public', 'Safety' {

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

    It 'never sends a request that names a rule without the seed prefix, and has no parameter that could' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHbacRule -Confirm:$false
            $ruleCalls = @($script:Calls | Where-Object { $_.Method -like 'hbacrule_*' })
            $ruleCalls.Count | Should-BeGreaterThan 0
            @($ruleCalls | Where-Object { $_.Arguments[0] -notlike 'zz-test-*' }) | Should-BeCollection -Count 0
            @($script:Calls | Where-Object { @($_.Arguments) -contains 'allow_all' -or @($_.Arguments) -contains 'allow_systemd-user' }) | Should-BeCollection -Count 0
            $parameters = (Get-Command New-FreeIPAHbacRule).Parameters.Keys
            $parameters | Should-NotContainCollection @('Force')
            $parameters | Should-NotContainCollection @('IncludeDefault')
        }
    }

    It 'creates services and service groups before the rules, sending a stock service by its own name and never creating it' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAHbacRule -PassThru -Confirm:$false

            $r.ServicesCreated | Should-Be 3
            $r.ServiceGroupsCreated | Should-Be 3
            $r.CreatedRules | Should-Be 7
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'hbacsvcgroup_add') | Should-BeLessThan ([array]::IndexOf($methods, 'hbacrule_add'))
            $remote = ($script:Calls | Where-Object { $_.Method -eq 'hbacsvcgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-remote-access' }).Options
            $remote.hbacsvc | Should-BeCollection @('sshd', 'login', 'zz-test-gitlab-shell')
            @($script:Calls | Where-Object { $_.Method -eq 'hbacsvc_add' } | ForEach-Object { $_.Arguments[0] }) | Should-BeCollection @('zz-test-payroll', 'zz-test-gitlab-shell', 'zz-test-vault-agent')
        }
    }

    It 'adds who, where and what after the rule exists, with a user and a group both admitted to payroll' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHbacRule -RuleName finance-payroll -Confirm:$false
            $users = ($script:Calls | Where-Object { $_.Method -eq 'hbacrule_add_user' }).Options
            $users.user | Should-BeCollection @('praghunathan')
            $users.group | Should-BeCollection @('zz-test-dept-finance')
            ($script:Calls | Where-Object { $_.Method -eq 'hbacrule_add_host' }).Options.host | Should-BeCollection @('zz-test-db01.zz-test-lab.ipa.example.com')
            ($script:Calls | Where-Object { $_.Method -eq 'hbacrule_add_service' }).Options.hbacsvcgroup | Should-BeCollection @('zz-test-finance-apps')
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'hbacrule_disable' }
        }
    }

    It 'creates the allow-everything rule with categories, no members, and switched off' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHbacRule -RuleName legacy-open-door -Confirm:$false
            $add = ($script:Calls | Where-Object { $_.Method -eq 'hbacrule_add' }).Options
            $add.usercategory | Should-Be 'all'
            $add.hostcategory | Should-Be 'all'
            $add.servicecategory | Should-Be 'all'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like 'hbacrule_add_*' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'hbacrule_disable' -and $Arguments[0] -eq 'zz-test-legacy-open-door' -and $IgnoreError -contains 'AlreadyInactive' }
        }
    }

    It 'modifies a rule that exists, re-enables one whose row says so, and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { if ($Type -eq 'HbacRules') { @([PSCustomObject]@{ cn = @('zz-test-staff-bastion'); description = @('x [ZZ-TEST-seed]') }) } else { @() } }
            $r = New-FreeIPAHbacRule -RuleName staff-bastion -PassThru -Confirm:$false
            $r.UpdatedRules | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'hbacrule_mod' -and $IgnoreError -contains 'EmptyModlist' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'hbacrule_enable' -and $IgnoreError -contains 'AlreadyActive' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAHbacRule -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}
