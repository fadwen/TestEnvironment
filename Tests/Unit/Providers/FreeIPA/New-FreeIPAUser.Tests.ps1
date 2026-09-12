#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The users step is where FreeIPA's lifecycle states and password rules meet the seed
    data, and each one is pinned: a staged user goes to the staging container and joins no
    group, a preserved user is created, placed and then preserved so the preservation strips
    something, a disabled user is disabled after creation and keeps its memberships, a
    manager exists before the person who reports to them, the tag and the class ride in
    userclass, a MustChange password is set as an administrator and a Current one is changed
    as the user afterwards, no password is set without -AccountPassword, the user with no
    private group takes the GID of a seeded group, and membership is one call per group.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'A test password typed into a test file.')]
param()

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAUser' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Get-FreeIPASeededObject { @() }
            Mock Set-FreeIPAPassword { }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                switch ($Method) {
                    'group_show' { return [PSCustomObject]@{ result = [PSCustomObject]@{ gidnumber = @('737200042') } } }
                    'group_add_member' { return [PSCustomObject]@{ completed = @($Options.user).Count; failed = $null } }
                    'group_add_member_manager' { return [PSCustomObject]@{ completed = @($Options.user).Count; failed = $null } }
                }
                [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @($Arguments[0]) } }
            }
            $script:Password = ConvertTo-SecureString -String 'Lab-Password-2026!xyzQ' -AsPlainText -Force
        }
    }

    It 'creates a manager before the person who reports to them, with the tag and class in userclass' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAUser -UserName zmueller, jnino, awhitfield -PassThru -Confirm:$false

            $r.CreatedUsers | Should-Be 3
            $adds = @($script:Calls | Where-Object { $_.Method -eq 'user_add' })
            $adds.Arguments | Should-BeCollection @('awhitfield', 'jnino', 'zmueller')
            $jose = ($adds | Where-Object { $_.Arguments[0] -eq 'jnino' }).Options
            $jose.userclass | Should-BeCollection @('ZZ-TEST-seed', 'employee')
            $jose.manager | Should-Be 'awhitfield'
            $jose.givenname | Should-Be 'José'
            $jose.ipauserauthtype | Should-BeCollection @('otp')
            $jose.ipasshpubkey.Count | Should-Be 1
            ($adds | Where-Object { $_.Arguments[0] -eq 'zmueller' }).Options.ipasshpubkey.Count | Should-Be 2
            ($adds | Where-Object { $_.Arguments[0] -eq 'zmueller' }).Options.homedirectory | Should-Be '/home/zurich/zmueller'
        }
    }

    It 'stages the hire, preserves the leaver after placing her, and disables the disabled account after creating it' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAUser -UserName lchen, rokafor, talvarez -PassThru -Confirm:$false

            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'stageuser_add' -and $Arguments[0] -eq 'lchen' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_disable' -and $Arguments[0] -eq 'talvarez' -and $IgnoreError -contains 'AlreadyInactive' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_del' -and $Arguments[0] -eq 'rokafor' -and $Options.preserve -eq $true }

            # The staged user joins nothing; the preserved and disabled ones are placed, and the
            # preserving delete comes after the placement it strips.
            $memberships = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member' })
            @($memberships | ForEach-Object { $_.Options.user } | Where-Object { $_ -eq 'lchen' }).Count | Should-Be 0
            @($memberships | ForEach-Object { $_.Options.user } | Where-Object { $_ -eq 'rokafor' }).Count | Should-BeGreaterThan 0
            @($memberships | ForEach-Object { $_.Options.user } | Where-Object { $_ -eq 'talvarez' }).Count | Should-BeGreaterThan 0
            [array]::LastIndexOf($methods, 'group_add_member') | Should-BeLessThan ([array]::IndexOf($methods, 'user_del'))
            $r.StagedUsers | Should-Be 1
            $r.PreservedUsers | Should-Be 1
            $r.DisabledUsers | Should-Be 1
        }
    }

    It 'sets no password without -AccountPassword, and with one sets MustChange as an admin and Current as the user' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAUser -UserName awhitfield, jnino -PassThru -Confirm:$false
            $r.PasswordsSet | Should-Be 0
            @($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Options.ContainsKey('userpassword') }).Count | Should-Be 0
            Should-NotInvoke Set-FreeIPAPassword

            $script:Calls.Clear()
            $r = New-FreeIPAUser -UserName awhitfield, jnino, nsorensen -AccountPassword $script:Password -PassThru -Confirm:$false
            $r.PasswordsSet | Should-Be 2
            # MustChange: the password itself, set by the administrator and therefore expired.
            ($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Arguments[0] -eq 'jnino' }).Options.userpassword | Should-Be 'Lab-Password-2026!xyzQ'
            # Current: a temporary one, then changed as the user to the real one.
            $ada = ($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Arguments[0] -eq 'awhitfield' }).Options
            $ada.userpassword | Should-NotBe 'Lab-Password-2026!xyzQ'
            Should-Invoke Set-FreeIPAPassword -Times 1 -Exactly -ParameterFilter { $Username -eq 'awhitfield' -and $OldPassword -eq $ada.userpassword -and $NewPassword -eq 'Lab-Password-2026!xyzQ' }
            # None: nothing.
            ($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Arguments[0] -eq 'nsorensen' }).Options.ContainsKey('userpassword') | Should-BeFalse
        }
    }

    It 'gives the user with no private group the GID of her seeded primary group, and an expired principal a past date' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -UserName ofitzgerald -Confirm:$false

            $add = ($script:Calls | Where-Object { $_.Method -eq 'user_add' }).Options
            $add.noprivate | Should-BeTrue
            $add.gidnumber | Should-Be 737200042
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'group_show' -and $Arguments[0] -eq 'zz-test-contractors' }
            $expiry = ConvertFrom-FreeIPADateTime -Value $add.krbprincipalexpiration
            $expiry | Should-BeLessThan ([DateTimeOffset]::UtcNow)
        }
    }

    It 'links a radius user to the seeded proxy and an idp user to the seeded provider, by realm name, with their login there' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -Username praghunathan, ofitzgerald -SkipGroups -Confirm:$false
            $priya = ($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Arguments[0] -eq 'praghunathan' }).Options
            $priya.ipauserauthtype | Should-BeCollection @('radius')
            $priya.ipatokenradiusconfiglink | Should-Be 'zz-test-legacy-radius'
            $priya.ipatokenradiususername | Should-Be 'praghu'
            $priya.ContainsKey('ipaidpconfiglink') | Should-BeFalse
            $orla = ($script:Calls | Where-Object { $_.Method -eq 'user_add' -and $_.Arguments[0] -eq 'ofitzgerald' }).Options
            $orla.ipauserauthtype | Should-BeCollection @('idp')
            $orla.ipaidpconfiglink | Should-Be 'zz-test-github'
            $orla.ipaidpsub | Should-Be 'ofitzgerald-gh'
            $orla.ContainsKey('ipatokenradiusconfiglink') | Should-BeFalse
        }
    }

    It 'adds the users the groups file names as member managers, once they exist, and only those in the run' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAUser -Username awhitfield, jnino, hkobayashi -PassThru -Confirm:$false
            $r.ManagersApplied | Should-Be 2
            $managers = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member_manager' })
            @($managers | ForEach-Object { $_.Arguments[0] }) | Should-BeCollection @('zz-test-dept-engineering', 'zz-test-team-platform')
            ($managers | Where-Object { $_.Arguments[0] -eq 'zz-test-dept-engineering' }).Options.user | Should-BeCollection @('awhitfield')
            ($managers | Where-Object { $_.Arguments[0] -eq 'zz-test-team-platform' }).Options.user | Should-BeCollection @('jnino')
            # After the last user_add, never before.
            $methods = [string[]]@($script:Calls | ForEach-Object { $_.Method })
            [array]::LastIndexOf($methods, 'user_add') | Should-BeLessThan ([array]::IndexOf($methods, 'group_add_member_manager'))
        }
    }

    It 'names no member manager when none of the users in the run is one' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -Username hkobayashi -Confirm:$false
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'group_add_member_manager' }
        }
    }

    It 'adds certificate mapping data to the one user who carries it' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -UserName awhitfield -Confirm:$false
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_add_certmapdata' -and $Arguments[0] -eq 'awhitfield' -and $Options.issuer -like 'CN=Lab Issuing CA*' -and $Options.subject -like 'CN=Ada Whitfield*' }
        }
    }

    It 'applies membership one call per group, naming the prefixed group' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -UserName jnino, zmueller -Confirm:$false
            $memberships = @($script:Calls | Where-Object { $_.Method -eq 'group_add_member' })
            @($memberships.Arguments | Sort-Object) | Should-BeCollection @('zz-test-all-staff', 'zz-test-dept-engineering', 'zz-test-site-zurich', 'zz-test-team-platform')
            ($memberships | Where-Object { $_.Arguments[0] -eq 'zz-test-team-platform' }).Options.user | Should-BeCollection @('jnino', 'zmueller')
        }
    }

    It 'modifies a user who exists and leaves a preserved one preserved' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject {
                switch ($Type) {
                    'Users' { @([PSCustomObject]@{ uid = @('jnino') }) }
                    'PreservedUsers' { @([PSCustomObject]@{ uid = @('rokafor') }) }
                    default { @() }
                }
            }
            $r = New-FreeIPAUser -UserName jnino, rokafor -PassThru -Confirm:$false
            $r.CreatedUsers | Should-Be 0
            $r.UpdatedUsers | Should-Be 2
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_mod' -and $Arguments[0] -eq 'jnino' -and $IgnoreError -contains 'EmptyModlist' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'user_del' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'user_add' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAUser -Tier Core -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }

    It 'records a failed row as an error and carries on with the rest' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                if ($Method -eq 'user_add' -and $Arguments[0] -eq 'jnino') { throw 'FreeIPA user_add failed (ValidationError 3009): invalid something' }
                if ($Method -eq 'group_add_member') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @($Arguments[0]) } }
            }
            $r = New-FreeIPAUser -UserName awhitfield, jnino -PassThru -Confirm:$false -ErrorAction SilentlyContinue
            $r.CreatedUsers | Should-Be 1
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString "user 'jnino'"
        }
    }
}
