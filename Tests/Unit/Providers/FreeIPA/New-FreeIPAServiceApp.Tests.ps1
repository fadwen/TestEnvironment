#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The bootstrap creates the one credential every later session runs on, and what it has to
    get right is FreeIPA's password behaviour: the random password the server hands back is
    expired on arrival, so it is changed as the user before it is stored; the realm's policy
    would expire the new one, so the expiry is pushed out; the record is written only after
    the vault is proven; and the account is proven by logging in with it. Pinned too: an
    existing account is refused without -Force, the tag rides in userclass, the account is
    added to admins, and the password never reaches the output.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAServiceApp' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; CaCertificate = '-----BEGIN CERTIFICATE-----'; ApiVersion = '2.257'; Client = 'client' } }
            Mock Write-Host { }
            Mock Get-FreeIPACredentialPath { 'C:\record.json' }
            Mock Set-FreeIPAPassword { }
            Mock Export-FreeIPACredential { [PSCustomObject]@{ Path = $Path; Protection = 'DPAPI'; VaultName = $null; SecretName = $null } }
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $true } }
            Mock New-FreeIPAHttpClient {
                $client = [PSCustomObject]@{ Disposed = $false }
                $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
                [PSCustomObject]@{ Client = $client; Cookies = $null }
            }
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $true; Reason = $null } }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                switch ($Method) {
                    'user_show' { return $null }
                    'user_add' { return [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @('zz-test-automation'); randompassword = 'RANDOM-FROM-SERVER' } } }
                    'group_add_member' { return [PSCustomObject]@{ completed = 1; failed = $null } }
                    'whoami' { return [PSCustomObject]@{ arguments = @('zz-test-automation') } }
                }
                [PSCustomObject]@{ result = [PSCustomObject]@{} }
            }
        }
    }

    It 'creates the account with the tag and no shell, makes its password current, extends the expiry and adds it to admins' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAServiceApp -PassThru -Confirm:$false

            $add = ($script:Calls | Where-Object { $_.Method -eq 'user_add' })
            $add.Arguments | Should-BeCollection @('zz-test-automation')
            $add.Options.userclass | Should-BeCollection @('ZZ-TEST-seed')
            $add.Options.loginshell | Should-Be '/sbin/nologin'
            $add.Options.random | Should-BeTrue
            Should-Invoke Set-FreeIPAPassword -Times 1 -Exactly -ParameterFilter { $Username -eq 'zz-test-automation' -and $OldPassword -eq 'RANDOM-FROM-SERVER' -and $NewPassword -ne 'RANDOM-FROM-SERVER' }
            $mod = ($script:Calls | Where-Object { $_.Method -eq 'user_mod' })
            (ConvertFrom-FreeIPADateTime -Value $mod.Options.krbpasswordexpiration) | Should-BeGreaterThan ([DateTimeOffset]::UtcNow.AddYears(9))
            $membership = ($script:Calls | Where-Object { $_.Method -eq 'group_add_member' })
            $membership.Arguments | Should-BeCollection @('admins')
            $membership.Options.user | Should-BeCollection @('zz-test-automation')
            $r.HandoverVerified | Should-BeTrue
            $r.Warnings | Should-BeCollection -Count 0
        }
    }

    It 'writes the record with the rotated password and the pinned CA, and never puts the password in the output' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAServiceApp -PassThru -Confirm:$false
            Should-Invoke Export-FreeIPACredential -Times 1 -Exactly -ParameterFilter { $Username -eq 'zz-test-automation' -and $Password -ne 'RANDOM-FROM-SERVER' -and $CaCertificate -like '-----BEGIN*' -and $Path -eq 'C:\record.json' }
            ($r | ConvertTo-Json -Depth 3) | Should-NotMatchString 'RANDOM-FROM-SERVER'
            $r.PSObject.Properties.Name | Should-NotContainCollection @('Password')
        }
    }

    It 'refuses an existing account without -Force and replaces it with' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                switch ($Method) {
                    'user_show' { return [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @('zz-test-automation') } } }
                    'user_add' { return [PSCustomObject]@{ result = [PSCustomObject]@{ randompassword = 'RANDOM-FROM-SERVER' } } }
                    'group_add_member' { return [PSCustomObject]@{ completed = 1; failed = $null } }
                    'whoami' { return [PSCustomObject]@{ arguments = @('zz-test-automation') } }
                }
                [PSCustomObject]@{ result = [PSCustomObject]@{} }
            }
            { New-FreeIPAServiceApp -Confirm:$false } | Should-Throw -ExceptionMessage '*already exists*-Force*'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'user_del' }

            $null = New-FreeIPAServiceApp -Force -Confirm:$false
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_del' -and $Arguments[0] -eq 'zz-test-automation' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'user_add' }
        }
    }

    It 'proves the vault before creating anything, and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $false } }
            { New-FreeIPAServiceApp -UseSecretStore -Confirm:$false } | Should-Throw -ExceptionMessage '*not usable*'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'user_add' }

            $null = New-FreeIPAServiceApp -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -ne 'user_show' }
        }
    }

    It 'reports a handover that did not authenticate as a warning rather than a success' {
        InModuleScope TestEnvironment {
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $false; Reason = 'invalid-password' } }
            $r = New-FreeIPAServiceApp -PassThru -Confirm:$false -WarningAction SilentlyContinue
            $r.HandoverVerified | Should-BeFalse
            @($r.Warnings | Where-Object { $_ -like '*did not authenticate*' }).Count | Should-Be 1
        }
    }
}
