#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The token is the one secret the session holds, and two commands can hand it back. Pinned:
    Get-AuthentikAccessToken returns it as a SecureString unless plain text is asked for by
    name, reads the record when the session runs as the service account or is not connected,
    and Get-AuthentikServiceApp never returns the token at all, proves it only when asked, and
    says where the record is when there is none.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AuthentikAccessToken' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Import-AuthentikCredential {
                [PSCustomObject]@{ BaseUrl = 'https://auth.example.com'; Username = 'zz-test-automation'; UserPk = 42; Token = 'RECORD-TOKEN'; Protection = 'DPAPI'; VaultName = $null; SecretName = $null; CreatedUtc = $null; Path = $Path }
            }
            Mock Get-AuthentikCredentialPath { 'C:\record.json' }
        }
    }

    It 'returns the session token as a SecureString, and as text only when asked by name' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer SESSION-TOKEN'; AuthType = 'ApiToken'; Identity = 'akadmin'; CredentialPath = $null } }

            $t = Get-AuthentikAccessToken
            ($t.Token -is [System.Security.SecureString]) | Should-BeTrue
            $t.Identity | Should-Be 'akadmin'
            ($t | ConvertTo-Json -Depth 3) | Should-NotMatchString 'SESSION-TOKEN'

            Get-AuthentikAccessToken -AsPlainText | Should-Be 'SESSION-TOKEN'
            Should-NotInvoke Import-AuthentikCredential
        }
    }

    It 'reads the record when the session runs as the service account' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer SESSION-TOKEN'; AuthType = 'ServiceAccount'; Identity = 'zz-test-automation'; CredentialPath = $null } }

            $t = Get-AuthentikAccessToken
            $t.AuthType | Should-Be 'ServiceAccount'
            $t.CredentialPath | Should-Be 'C:\record.json'
            Get-AuthentikAccessToken -AsPlainText | Should-Be 'RECORD-TOKEN'
        }
    }

    It 'reads the record for a named instance when not connected, and refuses with nothing to go on' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection { $null }

            Get-AuthentikAccessToken -BaseUrl 'https://auth.example.com' -AsPlainText | Should-Be 'RECORD-TOKEN'
            { Get-AuthentikAccessToken } | Should-Throw -ExceptionMessage '*Not connected*'
        }
    }
}

Describe 'Get-AuthentikServiceApp' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Record = Join-Path $TestDrive 'auth.example.com.serviceaccount.json'
            [System.IO.File]::WriteAllText($script:Record, '{}')
            Mock Get-AuthentikCredentialPath { $script:Record }
            Mock Import-AuthentikCredential {
                [PSCustomObject]@{ BaseUrl = 'https://auth.example.com'; Username = 'zz-test-automation'; UserPk = 42; Token = 'RECORD-TOKEN'; Protection = 'DPAPI'; VaultName = $null; SecretName = $null; CreatedUtc = '2026-09-10T00:00:00Z'; Path = $Path }
            }
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer SESSION-TOKEN'; AuthType = 'ApiToken'; Identity = 'akadmin'; CredentialPath = $null } }
            Mock Invoke-AuthentikRequest {
                if ($Path -eq '/core/users/me/') { return [PSCustomObject]@{ user = [PSCustomObject]@{ username = 'zz-test-automation' } } }
                [PSCustomObject]@{ pk = 42 }
            }
        }
    }

    It 'reports the record and whether the account exists, and never the token' {
        InModuleScope TestEnvironment {
            $s = Get-AuthentikServiceApp
            $s.Username | Should-Be 'zz-test-automation'
            $s.AccountExists | Should-BeTrue
            $s.CredentialWorks | Should-BeNull
            $s.PSObject.Properties.Name | Should-NotContainCollection @('Token')
            ($s | ConvertTo-Json -Depth 3) | Should-NotMatchString 'RECORD-TOKEN'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -eq '/core/users/me/' }
        }
    }

    It 'proves the stored credential only under -TestCredential, with the record token and not the session one' {
        InModuleScope TestEnvironment {
            $s = Get-AuthentikServiceApp -TestCredential
            $s.CredentialWorks | Should-BeTrue
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/core/users/me/' -and $Connection.AuthorizationHeader -eq 'Bearer RECORD-TOKEN' }
        }
    }

    It 'reports a credential that no longer authenticates as not working, without throwing' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Path -eq '/core/users/me/') { throw 'Authentik GET /core/users/me/ failed with HTTP 403: Token invalid/expired' }
                [PSCustomObject]@{ pk = 42 }
            }
            (Get-AuthentikServiceApp -TestCredential).CredentialWorks | Should-BeFalse
        }
    }

    It 'says where the record would be when there is none' {
        InModuleScope TestEnvironment {
            Remove-Item $script:Record -Force
            $s = Get-AuthentikServiceApp -WarningVariable warnings -WarningAction SilentlyContinue
            $s | Should-BeNull
            @($warnings | Where-Object { $_ -like "*$($script:Record)*New-TestServiceApp*" }).Count | Should-Be 1
        }
    }
}
