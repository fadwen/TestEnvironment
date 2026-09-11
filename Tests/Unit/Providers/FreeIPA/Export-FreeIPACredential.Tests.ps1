#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The credential record is the one file this provider writes that an attacker would want.
    Pinned: the password never sits in it as plaintext where the platform can protect it, the
    record round-trips through Import unchanged including the pinned CA, a SecretStore record
    holds only a pointer and the password comes back from the vault, the file and its folder
    are restricted to the current user, a record another machine wrote fails with an
    explanation rather than a stack trace, and a record with fields missing is refused before
    it can be used. The protection itself lives in Core and is exercised through it.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'A placeholder vault password typed into a test.')]
param()

$script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Export-FreeIPACredential and Import-FreeIPACredential' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Record = Join-Path (Join-Path $TestDrive 'creds') 'ipa.example.com.freeipa.json'
            Remove-Item -LiteralPath $script:Record -Force -ErrorAction SilentlyContinue
            $script:Vault = @{}
            $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $true } }
            Mock Set-TestVaultSecret { $script:Vault[$SecretName] = $PlainText }
            Mock Get-TestVaultSecret { $script:Vault[$SecretName] }
        }
    }

    It 'never writes the password as plaintext where the platform can protect it, and reads it and the CA back unchanged' {
        InModuleScope TestEnvironment {
            $written = Export-FreeIPACredential -Path $script:Record -BaseUrl 'https://ipa.example.com' -Username 'zz-test-automation' -Password 'SECRET-PASSWORD' -CaCertificate "-----BEGIN CERTIFICATE-----`nabc`n-----END CERTIFICATE-----" -Confirm:$false -WarningAction SilentlyContinue

            $text = [System.IO.File]::ReadAllText($script:Record)
            if ($script:OnWindows) {
                $written.Protection | Should-Be 'DPAPI'
                $text | Should-NotMatchString 'SECRET-PASSWORD'
            }
            else {
                $written.Protection | Should-Be 'None'
            }
            $text | Should-MatchString '"provider": *"FreeIPA"'

            $back = Import-FreeIPACredential -Path $script:Record -WarningAction SilentlyContinue
            $back.Password | Should-Be 'SECRET-PASSWORD'
            $back.Username | Should-Be 'zz-test-automation'
            $back.BaseUrl | Should-Be 'https://ipa.example.com'
            $back.CaCertificate | Should-MatchString 'BEGIN CERTIFICATE'
        }
    }

    It 'stores only a vault pointer under -UseSecretStore and reads the password from the vault' {
        InModuleScope TestEnvironment {
            $password = ConvertTo-SecureString -String 'vault-pass' -AsPlainText -Force
            $written = Export-FreeIPACredential -Path $script:Record -BaseUrl 'https://ipa.example.com' -Username 'zz-test-automation' -Password 'SECRET-PASSWORD' -UseSecretStore -VaultPassword $password -Confirm:$false

            $written.Protection | Should-Be 'SecretStore'
            $written.SecretName | Should-Be 'FreeIPAEnvironment-ipa.example.com-zz-test-automation'
            $text = [System.IO.File]::ReadAllText($script:Record)
            $text | Should-NotMatchString 'SECRET-PASSWORD'
            Should-Invoke Set-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $PlainText -eq 'SECRET-PASSWORD' }

            $back = Import-FreeIPACredential -Path $script:Record -VaultPassword $password
            $back.Password | Should-Be 'SECRET-PASSWORD'
            $back.Protection | Should-Be 'SecretStore'
            $back.CaCertificate | Should-BeNull
        }
    }

    It 'refuses to write anything when the vault is not usable' {
        InModuleScope TestEnvironment {
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $false } }
            { Export-FreeIPACredential -Path $script:Record -BaseUrl 'https://ipa.example.com' -Username 'u' -Password 'p' -UseSecretStore -Confirm:$false } | Should-Throw -ExceptionMessage '*not usable*'
            Test-Path $script:Record | Should-BeFalse
            Should-NotInvoke Set-TestVaultSecret
        }
    }

    It 'restricts the record and its folder to the current user' -Skip:(-not $script:OnWindows) {
        InModuleScope TestEnvironment {
            $null = Export-FreeIPACredential -Path $script:Record -BaseUrl 'https://ipa.example.com' -Username 'u' -Password 'p' -Confirm:$false -WarningAction SilentlyContinue

            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            foreach ($target in $script:Record, (Split-Path $script:Record -Parent)) {
                $acl = Get-Acl -LiteralPath $target
                $acl.AreAccessRulesProtected | Should-BeTrue
                $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
                @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) | Should-BeCollection @($me.Value)
            }
        }
    }

    It 'explains a record that another user or machine wrote rather than failing opaquely' -Skip:(-not $script:OnWindows) {
        InModuleScope TestEnvironment {
            $forged = @{ schemaVersion = 1; provider = 'FreeIPA'; baseUrl = 'https://ipa.example.com'; username = 'u'; protection = 'DPAPI'; passwordProtected = '01000000d08c9ddf0115d1118c7a00c04fc297eb0100000000' } | ConvertTo-Json
            [System.IO.File]::WriteAllText($script:Record, $forged)
            { Import-FreeIPACredential -Path $script:Record } | Should-Throw -ExceptionMessage '*could not be decrypted*New-TestServiceApp -Force*'
        }
    }

    It 'refuses a record with a required field missing, and a missing record with the command to run' {
        InModuleScope TestEnvironment {
            { Import-FreeIPACredential -Path (Join-Path $TestDrive 'nowhere.json') } | Should-Throw -ExceptionMessage '*New-TestServiceApp*'

            [System.IO.File]::WriteAllText($script:Record, (@{ baseUrl = 'https://ipa.example.com' } | ConvertTo-Json))
            { Import-FreeIPACredential -Path $script:Record } | Should-Throw -ExceptionMessage "*'username'*"
        }
    }

    It 'names the record by the server host under the user profile' {
        InModuleScope TestEnvironment {
            $path = Get-FreeIPACredentialPath -BaseUrl 'https://ipa.example.com:9443/'
            $path | Should-MatchString '\.testenvironment'
            (Split-Path $path -Leaf) | Should-Be 'ipa.example.com.freeipa.json'
            Get-FreeIPACredentialPath -BaseUrl 'https://ipa.example.com' -Path 'C:\elsewhere\x.json' | Should-Be 'C:\elsewhere\x.json'
            { Get-FreeIPACredentialPath -BaseUrl 'not a url' } | Should-Throw
        }
    }
}
