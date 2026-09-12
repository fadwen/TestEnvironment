#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Sudo rules grant root, and two things about the seed's handling of them are pinned. A sudo
    command is named by its path and cannot carry the prefix, so one that already exists in
    the realm without the marker is reused and never modified, and only one the seed made is
    ever deleted. And a rule's clauses go on after it exists: who, where, allow, deny, run-as
    - with a local account such as postgres sent as written, since FreeIPA stores it as an
    external run-as user - and each option as its own call. The disabled rule is disabled after
    creation; the shell-escape rule carries its option.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPASudoRule' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'sudocmd_show') { return $null }
                if ($Method -like '*_add_*') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates every command with the marker, then the groups, then the rules' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPASudoRule -PassThru -Confirm:$false
            $r.CommandsCreated | Should-Be 8
            $r.CommandGroupsCreated | Should-Be 4
            $r.CreatedRules | Should-Be 7
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'sudocmd_add' })
            $adds.Arguments | Should-ContainCollection '/usr/bin/vim'
            foreach ($add in $adds) { $add.Options.description | Should-MatchString '\[ZZ-TEST-seed\]$' }
            ($script:Calls | Where-Object { $_.Method -eq 'sudocmdgroup_add_member' -and $_.Arguments[0] -eq 'zz-test-editors' }).Options.sudocmd | Should-BeCollection @('/usr/bin/vim', '/usr/bin/less')
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'sudocmdgroup_add') | Should-BeLessThan ([array]::IndexOf($methods, 'sudorule_add'))
        }
    }

    It 'reuses a command that already exists in the realm without touching it' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'sudocmd_show') { if ($Arguments[0] -eq '/usr/bin/dnf') { return [PSCustomObject]@{ result = [PSCustomObject]@{ sudocmd = @('/usr/bin/dnf') } } } else { return $null } }
                if ($Method -like '*_add_*') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
            $r = New-FreeIPASudoRule -PassThru -Confirm:$false
            $r.CommandsReused | Should-Be 1
            $r.CommandsCreated | Should-Be 7
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Arguments[0] -eq '/usr/bin/dnf' -and $Method -in 'sudocmd_add', 'sudocmd_mod' }
        }
    }

    It 'adds every clause after the rule exists, sends a local run-as account as written, and each option on its own' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPASudoRule -RuleName dba-postgres, platform-services -Confirm:$false
            $dba = @($script:Calls | Where-Object { $_.Arguments[0] -eq 'zz-test-dba-postgres' })
            ($dba | Where-Object { $_.Method -eq 'sudorule_add' }).Options.sudoorder | Should-Be 20
            ($dba | Where-Object { $_.Method -eq 'sudorule_add_user' }).Options.user | Should-BeCollection @('jnino')
            ($dba | Where-Object { $_.Method -eq 'sudorule_add_host' }).Options.host | Should-BeCollection @('zz-test-db01.zz-test-lab.ipa.example.com')
            ($dba | Where-Object { $_.Method -eq 'sudorule_add_allow_command' }).Options.sudocmd | Should-BeCollection @('/usr/bin/psql')
            ($dba | Where-Object { $_.Method -eq 'sudorule_add_runasuser' }).Options.user | Should-BeCollection @('postgres')
            $platform = @($script:Calls | Where-Object { $_.Arguments[0] -eq 'zz-test-platform-services' })
            ($platform | Where-Object { $_.Method -eq 'sudorule_add_user' }).Options.group | Should-BeCollection @('zz-test-team-platform')
            ($platform | Where-Object { $_.Method -eq 'sudorule_add_allow_command' }).Options.sudocmdgroup | Should-BeCollection @('zz-test-service-control')
            ($platform | Where-Object { $_.Method -eq 'sudorule_add_option' }).Options.ipasudoopt | Should-Be '!authenticate'
            ($platform | Where-Object { $_.Method -eq 'sudorule_add_option' }).IgnoreError | Should-BeNull
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'sudorule_add_option' -and $IgnoreError -contains 'DuplicateEntry' -and $Arguments[0] -eq 'zz-test-platform-services' }
        }
    }

    It 'creates the disabled rule with every category, no clauses, and switched off' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPASudoRule -RuleName legacy-root-shell -Confirm:$false
            $add = ($script:Calls | Where-Object { $_.Method -eq 'sudorule_add' }).Options
            $add.cmdcategory | Should-Be 'all'
            $add.ipasudorunasusercategory | Should-Be 'all'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'sudorule_add_allow_command' -or $Method -eq 'sudorule_add_runasuser' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'sudorule_add_user' -and $Options.user -contains 'talvarez' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'sudorule_disable' -and $Arguments[0] -eq 'zz-test-legacy-root-shell' }
        }
    }

    It 'sends an allow and a deny in one rule, and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPASudoRule -RuleName runner-reboot -Confirm:$false
            ($script:Calls | Where-Object { $_.Method -eq 'sudorule_add_allow_command' }).Options.sudocmd | Should-BeCollection @('/usr/sbin/reboot')
            ($script:Calls | Where-Object { $_.Method -eq 'sudorule_add_deny_command' }).Options.sudocmd | Should-BeCollection @('/usr/bin/dnf')
            ($script:Calls | Where-Object { $_.Method -eq 'sudorule_add' }).Options.usercategory | Should-Be 'all'
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPASudoRule -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}
