#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Connecting is the one step every other command depends on, and its failure modes are
    quiet: a connection stored before it was proven leaves every later command failing with
    an unrelated message, and a -PassThru that carried the password would put it in every
    transcript. Both are pinned here, along with what FreeIPA does to passwords - an admin-set
    one is expired on arrival, and the realm's policy expires the service account's on its own
    schedule - and what the connect does about each: change a bootstrap credential only when
    told the new password, rotate the service account's on its own and rewrite the record.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test passwords, typed into a test file.')]
param()

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-FreeIPAEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:FreeIPAConnection = $null
            $script:Credential = [pscredential]::new('admin', (ConvertTo-SecureString -String 'admin-pw' -AsPlainText -Force))
            Mock New-FreeIPAHttpClient {
                $client = [PSCustomObject]@{ Disposed = $false }
                $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
                [PSCustomObject]@{ Client = $client; Cookies = $null }
            }
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $true; Reason = $null } }
            Mock Invoke-FreeIPARequest {
                switch ($Method) {
                    'ping' { [PSCustomObject]@{ summary = 'IPA server version 4.13.1. API version 2.257' } }
                    'whoami' { [PSCustomObject]@{ arguments = @($Connection.Username) } }
                    'env' { [PSCustomObject]@{ result = [PSCustomObject]@{ domain = 'ipa.example.com'; realm = 'IPA.EXAMPLE.COM' } } }
                }
            }
            Mock Set-FreeIPAPassword { }
            Mock Export-FreeIPACredential { [PSCustomObject]@{ Path = $Path; Protection = 'DPAPI' } }
        }
    }

    It 'stores nothing when the login is refused' {
        InModuleScope TestEnvironment {
            Mock Connect-FreeIPASession { [PSCustomObject]@{ Success = $false; Reason = 'invalid-password' } }

            { Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential } |
                Should-Throw -ExceptionMessage '*Could not authenticate*invalid-password*'

            $script:FreeIPAConnection | Should-BeNull
        }
    }

    It 'stores the connection with what the server said about itself' {
        InModuleScope TestEnvironment {
            Connect-FreeIPAEnvironment -BaseUrl 'https://ipa.example.com/' -Credential $script:Credential

            $script:FreeIPAConnection.BaseUrl | Should-Be 'https://ipa.example.com'
            $script:FreeIPAConnection.Username | Should-Be 'admin'
            $script:FreeIPAConnection.Password | Should-Be 'admin-pw'
            $script:FreeIPAConnection.AuthType | Should-Be 'Credential'
            $script:FreeIPAConnection.ApiVersion | Should-Be '2.257'
            $script:FreeIPAConnection.Domain | Should-Be 'ipa.example.com'
            $script:FreeIPAConnection.Realm | Should-Be 'IPA.EXAMPLE.COM'
            $script:FreeIPAConnection.Prefix | Should-Be 'ZZ-TEST-'
            $script:FreeIPAConnection.SeedTag | Should-Be 'ZZ-TEST-seed'
        }
    }

    It 'never returns the password or the client' {
        InModuleScope TestEnvironment {
            $result = Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential -PassThru

            $result.PSObject.Properties.Name | Should-NotContainCollection @('Password')
            $result.PSObject.Properties.Name | Should-NotContainCollection @('Client')
            ($result | ConvertTo-Json -Depth 3) | Should-NotMatchString 'admin-pw'
            $result.Identity | Should-Be 'admin'
            $result.PinnedCa | Should-BeFalse
        }
    }

    It 'refuses an expired bootstrap password unless told the new one, and changes it when told' {
        InModuleScope TestEnvironment {
            $script:Logins = 0
            Mock Connect-FreeIPASession {
                $script:Logins++
                if ($script:Logins -eq 1) { return [PSCustomObject]@{ Success = $false; Reason = 'password-expired' } }
                [PSCustomObject]@{ Success = $true; Reason = $null }
            }

            { Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential } |
                Should-Throw -ExceptionMessage '*expired*-NewPassword*'
            Should-NotInvoke Set-FreeIPAPassword

            $script:Logins = 0
            Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential -NewPassword (ConvertTo-SecureString -String 'fresh-pw' -AsPlainText -Force)
            Should-Invoke Set-FreeIPAPassword -Times 1 -Exactly -ParameterFilter { $Username -eq 'admin' -and $OldPassword -eq 'admin-pw' -and $NewPassword -eq 'fresh-pw' }
            $script:FreeIPAConnection.Password | Should-Be 'fresh-pw'
        }
    }

    It 'reads the record under -ServiceAccount, trusts the CA it carries, and rotates an expired password' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPACredentialPath { 'C:\record.json' }
            Mock Import-FreeIPACredential {
                [PSCustomObject]@{ BaseUrl = 'https://ipa.example.com'; Username = 'zz-test-automation'; Password = 'old-pw'; CaCertificate = '-----BEGIN CERTIFICATE-----x'; Protection = 'DPAPI'; VaultName = $null }
            }
            $script:Logins = 0
            Mock Connect-FreeIPASession {
                $script:Logins++
                if ($script:Logins -eq 1) { return [PSCustomObject]@{ Success = $false; Reason = 'password-expired' } }
                [PSCustomObject]@{ Success = $true; Reason = $null }
            }

            Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -ServiceAccount -WarningAction SilentlyContinue

            Should-Invoke New-FreeIPAHttpClient -Times 1 -Exactly -ParameterFilter { $CaCertificate -like '-----BEGIN CERTIFICATE-----*' }
            Should-Invoke Set-FreeIPAPassword -Times 1 -Exactly -ParameterFilter { $Username -eq 'zz-test-automation' -and $OldPassword -eq 'old-pw' }
            Should-Invoke Export-FreeIPACredential -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\record.json' -and $Password -ne 'old-pw' -and $CaCertificate -like '-----BEGIN*' }
            $script:FreeIPAConnection.AuthType | Should-Be 'ServiceAccount'
            $script:FreeIPAConnection.Identity | Should-Be 'zz-test-automation'
            $script:FreeIPAConnection.CredentialPath | Should-Be 'C:\record.json'
        }
    }

    It 'derives the domain from the server name when the realm does not report one, and refuses when it cannot' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                switch ($Method) {
                    'ping' { [PSCustomObject]@{ summary = 'IPA server version 4.13.1. API version 2.257' } }
                    'whoami' { [PSCustomObject]@{ arguments = @('admin') } }
                    'env' { throw 'FreeIPA env failed' }
                }
            }

            Connect-FreeIPAEnvironment -BaseUrl https://ipa.lab.example.com -Credential $script:Credential -WarningAction SilentlyContinue
            $script:FreeIPAConnection.Domain | Should-Be 'lab.example.com'

            $script:FreeIPAConnection = $null
            { Connect-FreeIPAEnvironment -BaseUrl https://ipa -Credential $script:Credential -WarningAction SilentlyContinue } | Should-Throw -ExceptionMessage '*cannot be derived*'
            $script:FreeIPAConnection | Should-BeNull
        }
    }

    It 'rejects a prefix with no trailing separator and a CA file that is not PEM' {
        InModuleScope TestEnvironment {
            { Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential -Prefix 'LAB' } | Should-Throw
            $notPem = Join-Path $TestDrive 'ca.txt'
            [System.IO.File]::WriteAllText($notPem, 'not a certificate')
            { Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential $script:Credential -CertificateAuthorityPath $notPem } | Should-Throw -ExceptionMessage '*PEM*'
        }
    }
}

Describe 'Disconnect-FreeIPAEnvironment' -Tag 'Unit', 'Public' {

    It 'clears the connection and is silent when there is none' {
        InModuleScope TestEnvironment {
            $script:FreeIPAConnection = @{ BaseUrl = 'https://ipa.example.com'; Identity = 'admin'; Client = $null }
            $r = Disconnect-FreeIPAEnvironment -PassThru -Confirm:$false
            $r.BaseUrl | Should-Be 'https://ipa.example.com'
            $script:FreeIPAConnection | Should-BeNull

            # Silent with nothing connected: a throw here fails the test.
            Disconnect-FreeIPAEnvironment -Confirm:$false
            $script:FreeIPAConnection | Should-BeNull
        }
    }
}
