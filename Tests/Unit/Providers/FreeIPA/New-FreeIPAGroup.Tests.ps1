#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Groups and host groups are the containers everything else joins, and two things about
    them are easy to get silently wrong: a child nested before its parent exists, and a
    re-run that creates a duplicate or changes a type FreeIPA cannot change. Pinned: depth
    order, the prefix and the marker on every create, the type flags, nesting applied as
    membership of the parent after every group exists, a re-run that modifies rather than
    adds and tolerates an empty modlist, and the 'already a member' answer treated as success.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAGroup' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'group_add_member') { return [PSCustomObject]@{ completed = @($Options.group).Count; failed = [PSCustomObject]@{ member = [PSCustomObject]@{ group = @() } } } }
                if ($Method -eq 'group_add_member_manager') { return [PSCustomObject]@{ completed = (@($Options.user | Where-Object { $_ }).Count + @($Options.group | Where-Object { $_ }).Count); failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates the chain in depth order, with the prefix, the marker and the type each row asks for' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAGroup -GroupName team-platform, all-staff, dept-engineering, ext-partners, ext-partners-posix -PassThru -Confirm:$false

            $r.CreatedGroups | Should-Be 5
            $r.Errors | Should-BeCollection -Count 0
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'group_add' })
            $adds.Arguments | Should-BeCollection @('zz-test-all-staff', 'zz-test-ext-partners-posix', 'zz-test-dept-engineering', 'zz-test-ext-partners', 'zz-test-team-platform')
            foreach ($add in $adds) { $add.Options.description | Should-MatchString '\[ZZ-TEST-seed\]$' }
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-team-platform' }).Options.nonposix | Should-BeTrue
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-ext-partners' }).Options.external | Should-BeTrue
            ($adds | Where-Object { $_.Arguments[0] -eq 'zz-test-all-staff' }).Options.ContainsKey('nonposix') | Should-BeFalse
        }
    }

    It 'adds the manager groups a row names by realm name after every group exists, and leaves the manager users to the users step' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAGroup -Tier Core -PassThru -Confirm:$false
            $r.ManagersApplied | Should-Be 1
            $r.ManagersDeferred | Should-Be 2
            $managers = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member_manager' })
            @($managers | ForEach-Object { $_.Arguments[0] }) | Should-BeCollection @('zz-test-contractors')
            ($managers | Where-Object { $_.Arguments[0] -eq 'zz-test-contractors' }).Options.group | Should-BeCollection @('zz-test-lab-admins')
            # No user is named before any user exists.
            @($managers | Where-Object { $_.Options.ContainsKey('user') }) | Should-BeCollection -Count 0
            # After the last group_add, never before.
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'group_add') | Should-BeLessThan ([array]::IndexOf($methods, 'group_add_member_manager'))
        }
    }

    It 'nests by adding children as members of the parent, after every group exists' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAGroup -GroupName all-staff, dept-engineering, team-platform -PassThru -Confirm:$false

            $nests = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member' })
            $nests.Count | Should-Be 2
            ($nests | Where-Object { $_.Arguments[0] -eq 'zz-test-all-staff' }).Options.group | Should-BeCollection @('zz-test-dept-engineering')
            ($nests | Where-Object { $_.Arguments[0] -eq 'zz-test-dept-engineering' }).Options.group | Should-BeCollection @('zz-test-team-platform')
            $r.NestingsApplied | Should-Be 2
            # Every add came before any nesting.
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'group_add') | Should-BeLessThan ([array]::IndexOf($methods, 'group_add_member'))
        }
    }

    It 'skips a parent that neither exists nor is selected, with a warning, and nests under one that already exists' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-dept-engineering'); description = @('Engineering [ZZ-TEST-seed]') }) }

            $r = New-FreeIPAGroup -GroupName team-platform, dept-sales -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            $r.CreatedGroups | Should-Be 2
            @($warnings | Where-Object { $_ -like "*names parent 'all-staff'*" }).Count | Should-Be 1
            $nests = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member' })
            $nests.Arguments | Should-BeCollection @('zz-test-dept-engineering')
        }
    }

    It 'modifies a group that already exists rather than adding it, and tolerates nothing to change' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-all-staff'); description = @('Every internal employee [ZZ-TEST-seed]') }) }

            $r = New-FreeIPAGroup -GroupName all-staff -PassThru -Confirm:$false

            $r.CreatedGroups | Should-Be 0
            $r.UpdatedGroups | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'group_mod' -and $IgnoreError -contains 'EmptyModlist' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'group_add' }
        }
    }

    It 'treats an existing membership as success and any other failure as an error' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                if ($Method -eq 'group_add_member') {
                    return [PSCustomObject]@{ completed = 0; failed = [PSCustomObject]@{ member = [PSCustomObject]@{ group = @(, @('zz-test-dept-engineering', 'This entry is already a member')) } } }
                }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
            $r = New-FreeIPAGroup -GroupName all-staff, dept-engineering -PassThru -Confirm:$false
            $r.Errors | Should-BeCollection -Count 0

            Mock Invoke-FreeIPARequest {
                if ($Method -eq 'group_add_member') {
                    return [PSCustomObject]@{ completed = 0; failed = [PSCustomObject]@{ member = [PSCustomObject]@{ group = @(, @('zz-test-dept-engineering', 'no such entry')) } } }
                }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
            $r = New-FreeIPAGroup -GroupName all-staff, dept-engineering -PassThru -Confirm:$false -ErrorAction SilentlyContinue
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'no such entry'
        }
    }

    It 'refuses an unknown name and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            { New-FreeIPAGroup -GroupName nope -Confirm:$false } | Should-Throw -ExceptionMessage '*No definition*nope*'
            $null = New-FreeIPAGroup -Tier Core -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPAHostgroup' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -eq 'hostgroup_add_member') { return [PSCustomObject]@{ completed = @($Options.hostgroup).Count; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates the parent before the children and nests them under it in one call' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAHostgroup -HostgroupName web-servers, db-servers, all-servers -PassThru -Confirm:$false

            $r.CreatedHostgroups | Should-Be 3
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'hostgroup_add' })
            $adds.Arguments[0] | Should-Be 'zz-test-all-servers'
            foreach ($add in $adds) { $add.Options.description | Should-MatchString '\[ZZ-TEST-seed\]$' }
            $nests = @($script:Calls | Where-Object { $_.Method -eq 'hostgroup_add_member' })
            $nests.Count | Should-Be 1
            $nests[0].Arguments[0] | Should-Be 'zz-test-all-servers'
            @($nests[0].Options.hostgroup | Sort-Object) | Should-BeCollection @('zz-test-db-servers', 'zz-test-web-servers')
            $r.NestingsApplied | Should-Be 2
        }
    }

    It 'modifies an existing host group and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-all-servers'); description = @('Every server [ZZ-TEST-seed]') }) }
            $r = New-FreeIPAHostgroup -HostgroupName all-servers -PassThru -Confirm:$false
            $r.UpdatedHostgroups | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'hostgroup_mod' }

            $null = New-FreeIPAHostgroup -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like '*_add*' }
        }
    }
}
