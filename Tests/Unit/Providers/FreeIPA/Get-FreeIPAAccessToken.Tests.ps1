#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The session cookie is the credential a script would need to call the API as the seed's
    identity, and the service-app status is the thing a person reads when a connect has
    failed. Pinned: the cookie comes back as a SecureString unless plain text is asked for by
    name, nothing is returned when the connection holds no session, and the status never
    carries the password while it proves the record's password by logging in with it.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreeIPAAccessToken' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $jar = [System.Net.CookieContainer]::new()
            $jar.Add([uri]'https://ipa.example.com', [System.Net.Cookie]::new('ipa_session', 'SESSION-COOKIE'))
            $script:FreeIPAConnection = @{ BaseUrl = 'https://ipa.example.com'; Identity = 'zz-test-automation'; AuthType = 'ServiceAccount'; Cookies = $jar; Password = 'SECRET' }
        }
    }

    AfterEach {
        InModuleScope TestEnvironment { $script:FreeIPAConnection = $null }
    }

    It 'returns the session cookie as a SecureString, and as text only when asked by name' {
        InModuleScope TestEnvironment {
            $t = Get-FreeIPAAccessToken
            ($t.Token -is [System.Security.SecureString]) | Should-BeTrue
            $t.CookieName | Should-Be 'ipa_session'
            $t.Referer | Should-Be 'https://ipa.example.com/ipa'
            ($t | ConvertTo-Json -Depth 3) | Should-NotMatchString 'SESSION-COOKIE'
            ($t | ConvertTo-Json -Depth 3) | Should-NotMatchString 'SECRET'

            Get-FreeIPAAccessToken -AsPlainText | Should-Be 'SESSION-COOKIE'
        }
    }

    It 'refuses when the connection holds no session, and when nothing is connected' {
        InModuleScope TestEnvironment {
            $script:FreeIPAConnection.Cookies = [System.Net.CookieContainer]::new()
            { Get-FreeIPAAccessToken } | Should-Throw -ExceptionMessage '*no session cookie*'
            $script:FreeIPAConnection = $null
            { Get-FreeIPAAccessToken } | Should-Throw -ExceptionMessage '*Not connected*'
        }
    }
}

Describe 'Get-FreeIPAServiceApp' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Record = Join-Path $TestDrive 'ipa.example.com.freeipa.json'
            [System.IO.File]::WriteAllText($script:Record, '{}')
            Mock Get-FreeIPACredentialPath { $script:Record }
            Mock Import-FreeIPACredential {
                [PSCustomObject]@{ BaseUrl = 'https://ipa.example.com'; Username = 'zz-test-automation'; Password = 'RECORD-PASSWORD'; CaCertificate = '-----BEGIN CERTIFICATE-----'; Protection = 'DPAPI'; VaultName = $null; SecretName = $null; CreatedUtc = '2026-09-10T00:00:00Z'; Path = $Path }
            }
            $script:FreeIPAConnection = @{ BaseUrl = 'https://ipa.example.com'; Username = 'admin'; Password = 'ADMIN-PASSWORD'; AuthType = 'Credential'; Identity = 'admin'; CredentialPath = $null; Client = 'client' }
            Mock Invoke-FreeIPARequest { [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @('zz-test-automation') } } }
            Mock New-FreeIPAHttpClient {
                $client = [PSCustomObject]@{ Disposed = $false }
                $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
                [PSCustomObject]@{ Client = $client; Cookies = $null }
            }
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $true; Reason = $null } }
        }
    }

    AfterEach {
        InModuleScope TestEnvironment { $script:FreeIPAConnection = $null }
    }

    It 'reports the record and whether the account exists, and never the password' {
        InModuleScope TestEnvironment {
            $s = Get-FreeIPAServiceApp
            $s.Username | Should-Be 'zz-test-automation'
            $s.AccountExists | Should-BeTrue
            $s.CredentialWorks | Should-BeNull
            $s.PinnedCa | Should-BeTrue
            $s.PSObject.Properties.Name | Should-NotContainCollection @('Password')
            ($s | ConvertTo-Json -Depth 3) | Should-NotMatchString 'RECORD-PASSWORD'
            Should-NotInvoke Connect-FreeIPASession
        }
    }

    It 'proves the stored password only under -TestCredential, with the record password and a client of its own' {
        InModuleScope TestEnvironment {
            $s = Get-FreeIPAServiceApp -TestCredential
            $s.CredentialWorks | Should-BeTrue
            Should-Invoke New-FreeIPAHttpClient -Times 1 -Exactly -ParameterFilter { $CaCertificate -like '-----BEGIN*' }
            Should-Invoke Connect-FreeIPASession -Times 1 -Exactly -ParameterFilter { $Connection.Username -eq 'zz-test-automation' -and $Connection.Password -eq 'RECORD-PASSWORD' }
        }
    }

    It 'reports a password that no longer authenticates as not working, without throwing' {
        InModuleScope TestEnvironment {
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $false; Reason = 'invalid-password' } }
            (Get-FreeIPAServiceApp -TestCredential).CredentialWorks | Should-BeFalse
        }
    }

    It 'says where the record would be when there is none' {
        InModuleScope TestEnvironment {
            Remove-Item $script:Record -Force
            $s = Get-FreeIPAServiceApp -WarningVariable warnings -WarningAction SilentlyContinue
            $s | Should-BeNull
            @($warnings | Where-Object { $_ -like "*$($script:Record)*New-TestServiceApp*" }).Count | Should-Be 1
        }
    }
}
