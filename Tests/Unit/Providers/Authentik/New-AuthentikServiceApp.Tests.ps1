#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The bootstrap creates a superuser credential, so these tests are mostly about what it
    refuses to do and the order it does the rest in: no replacement without -Force, the
    vault proven before the account exists, the account stamped and given rights before its
    token is written, and success reported only after the token has authenticated.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikServiceApp' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Write-Host { }
            Mock Get-AuthentikCredentialPath { Join-Path $TestDrive 'auth.example.com.serviceaccount.json' }
            Mock Export-AuthentikCredential { [PSCustomObject]@{ Path = $Path; Protection = 'DPAPI'; VaultName = $null; SecretName = $null } }
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $true } }

            $script:Calls = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-AuthentikRequest {
                $script:Calls.Add("$Method $Path")
                if ($Method -eq 'GET' -and $Path -eq '/core/users/') {
                    if ($Query['is_superuser']) { return @() }
                    return @()
                }
                if ($Method -eq 'GET' -and $Path -eq '/core/groups/') { return @([PSCustomObject]@{ pk = 'admins'; name = 'authentik Admins' }) }
                if ($Method -eq 'POST' -and $Path -eq '/core/users/service_account/') {
                    return [PSCustomObject]@{ username = 'zz-test-automation'; token = 'app-password-token'; user_pk = 42 }
                }
                if ($Method -eq 'GET' -and $Path -eq '/core/tokens/') { return @([PSCustomObject]@{ identifier = 'service-account-zz-test-automation-password' }) }
                if ($Method -eq 'POST' -and $Path -eq '/core/tokens/') { return [PSCustomObject]@{ identifier = $Body.identifier } }
                if ($Method -eq 'GET' -and $Path -eq '/core/tokens/zz-test-automation-api/view_key/') { return [PSCustomObject]@{ key = 'new-token' } }
                if ($Method -eq 'GET' -and $Path -eq '/core/users/me/') {
                    if ($Connection.AuthorizationHeader -eq 'Bearer new-token') { return [PSCustomObject]@{ user = [PSCustomObject]@{ username = 'zz-test-automation' } } }
                }
                return $null
            }
        }
    }

    It 'refuses to replace an existing account without -Force' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/core/users/') { return @([PSCustomObject]@{ pk = 7; username = 'zz-test-automation' }) }
                throw "unexpected $Method $Path"
            }

            { New-AuthentikServiceApp -Confirm:$false } | Should-Throw -ExceptionMessage '*already exists*'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'creates the account, stamps it, grants it superuser rights, writes the record and proves the token' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikServiceApp -PassThru -Confirm:$false

            $r.Username | Should-Be 'zz-test-automation'
            $r.UserPk | Should-Be 42
            $r.SuperuserGroup | Should-Be 'authentik Admins'
            $r.HandoverVerified | Should-BeTrue
            @($r.Warnings).Count | Should-Be 0

            $script:Calls.IndexOf('POST /core/users/service_account/') | Should-BeLessThan $script:Calls.IndexOf('PATCH /core/users/42/')
            $script:Calls.IndexOf('PATCH /core/users/42/') | Should-BeLessThan $script:Calls.IndexOf('POST /core/groups/admins/add_user/')
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.path -eq 'zz-test' -and $Body.attributes.labSeedTag -eq 'ZZ-TEST-seed' }
            Should-Invoke Export-AuthentikCredential -Times 1 -Exactly -ParameterFilter { $Token -eq 'new-token' -and $UserPk -eq 42 }
        }
    }

    It 'asks for no group of its own' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikServiceApp -Confirm:$false
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq '/core/users/service_account/' -and $Body.create_group -eq $false
            }
        }
    }

    It 'replaces the app-password token with a non-expiring api-intent token and stores that key' {
        # The creation call's token is refused as a bearer credential: a live run answered
        # 'Token invalid/expired'. The api-intent token is the one that works, and its key
        # is only ever handed back by view_key.
        InModuleScope TestEnvironment {
            $null = New-AuthentikServiceApp -Confirm:$false

            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq '/core/tokens/service-account-zz-test-automation-password/' }
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/core/tokens/' -and $Body.intent -eq 'api' -and $Body.expiring -eq $false -and $Body.user -eq 42
            }
            Should-Invoke Export-AuthentikCredential -Times 1 -Exactly -ParameterFilter { $Token -eq 'new-token' }
            Should-NotInvoke Export-AuthentikCredential -ParameterFilter { $Token -eq 'app-password-token' }
        }
    }

    It 'proves the vault before creating anything under -UseSecretStore' {
        InModuleScope TestEnvironment {
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $false } }

            { New-AuthentikServiceApp -UseSecretStore -Confirm:$false } | Should-Throw -ExceptionMessage '*not usable*'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'reports the handover unverified when the new token does not authenticate' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/core/users/') { return @() }
                if ($Method -eq 'GET' -and $Path -eq '/core/groups/') { return @([PSCustomObject]@{ pk = 'admins'; name = 'authentik Admins' }) }
                if ($Path -eq '/core/users/service_account/') { return [PSCustomObject]@{ token = 'x'; user_pk = 42 } }
                if ($Method -eq 'GET' -and $Path -eq '/core/tokens/') { return @() }
                if ($Path -like '*/view_key/') { return [PSCustomObject]@{ key = 'new-token' } }
                if ($Path -eq '/core/users/me/') { throw 'Authentik GET /core/users/me/ failed with HTTP 403: Invalid token.' }
                return $null
            }

            $r = New-AuthentikServiceApp -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.HandoverVerified | Should-BeFalse
            @($r.Warnings).Count | Should-Be 1
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikServiceApp -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
            Should-NotInvoke Export-AuthentikCredential
        }
    }
}
