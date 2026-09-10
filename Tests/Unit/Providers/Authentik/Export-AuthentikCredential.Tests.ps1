#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The credential record is the one file this provider writes that an attacker would want.
    Pinned: the token never sits in it as plaintext where the platform can protect it, the
    record round-trips through Import unchanged, a SecretStore record holds only a pointer and
    the token comes back from the vault, the file and its folder are restricted to the current
    user, a record another user or machine wrote fails with an explanation rather than a
    stack trace, and a record with fields missing is refused before it can be used.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'A placeholder vault password typed into a test.')]
param()

# Evaluated at discovery, because -Skip is decided before any BeforeAll runs.
$script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Export-AuthentikCredential and Import-AuthentikCredential' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Record = Join-Path (Join-Path $TestDrive 'creds') 'auth.example.com.serviceaccount.json'
            Remove-Item -LiteralPath $script:Record -Force -ErrorAction SilentlyContinue
            $script:Vault = @{}
            # Module scope, because an InModuleScope block cannot see the test file's variables.
            $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $true } }
            Mock Set-TestVaultSecret { $script:Vault[$SecretName] = $PlainText }
            Mock Get-TestVaultSecret { $script:Vault[$SecretName] }
        }
    }

    It 'never writes the token as plaintext where the platform can protect it, and reads it back unchanged' {
        InModuleScope TestEnvironment {
            $written = Export-AuthentikCredential -Path $script:Record -BaseUrl 'https://auth.example.com' -Username 'zz-test-automation' -UserPk 42 -Token 'SECRET-TOKEN-VALUE' -Confirm:$false -WarningAction SilentlyContinue

            $text = [System.IO.File]::ReadAllText($script:Record)
            if ($script:OnWindows) {
                $written.Protection | Should-Be 'DPAPI'
                $text | Should-NotMatchString 'SECRET-TOKEN-VALUE'
            }
            else {
                # Off Windows there is no DPAPI, and the fallback says so loudly.
                $written.Protection | Should-Be 'None'
            }

            $back = Import-AuthentikCredential -Path $script:Record -WarningAction SilentlyContinue
            $back.Token | Should-Be 'SECRET-TOKEN-VALUE'
            $back.Username | Should-Be 'zz-test-automation'
            $back.UserPk | Should-Be 42
            $back.BaseUrl | Should-Be 'https://auth.example.com'
        }
    }

    It 'stores only a vault pointer under -UseSecretStore and reads the token from the vault' {
        InModuleScope TestEnvironment {
            $password = ConvertTo-SecureString -String 'vault-pass' -AsPlainText -Force
            $written = Export-AuthentikCredential -Path $script:Record -BaseUrl 'https://auth.example.com' -Username 'zz-test-automation' -UserPk 42 -Token 'SECRET-TOKEN-VALUE' -UseSecretStore -VaultPassword $password -Confirm:$false

            $written.Protection | Should-Be 'SecretStore'
            $written.SecretName | Should-Be 'AuthentikEnvironment-auth.example.com-zz-test-automation'
            $text = [System.IO.File]::ReadAllText($script:Record)
            $text | Should-NotMatchString 'SECRET-TOKEN-VALUE'
            $text | Should-MatchString 'AuthentikEnvironment-auth.example.com-zz-test-automation'
            Should-Invoke Set-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $PlainText -eq 'SECRET-TOKEN-VALUE' }

            $back = Import-AuthentikCredential -Path $script:Record -VaultPassword $password
            $back.Token | Should-Be 'SECRET-TOKEN-VALUE'
            $back.Protection | Should-Be 'SecretStore'
            Should-Invoke Get-TestVaultSecret -Times 1 -Exactly
        }
    }

    It 'refuses to write anything when the vault is not usable' {
        InModuleScope TestEnvironment {
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $false } }
            { Export-AuthentikCredential -Path $script:Record -BaseUrl 'https://auth.example.com' -Username 'u' -UserPk 1 -Token 't' -UseSecretStore -Confirm:$false } | Should-Throw -ExceptionMessage '*not usable*'
            Test-Path $script:Record | Should-BeFalse
            Should-NotInvoke Set-TestVaultSecret
        }
    }

    It 'restricts the record and its folder to the current user' -Skip:(-not $script:OnWindows) {
        InModuleScope TestEnvironment {
            $null = Export-AuthentikCredential -Path $script:Record -BaseUrl 'https://auth.example.com' -Username 'u' -UserPk 1 -Token 't' -Confirm:$false -WarningAction SilentlyContinue

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
            $forged = @{ schemaVersion = 1; baseUrl = 'https://auth.example.com'; username = 'u'; userPk = 1; protection = 'DPAPI'; tokenProtected = '01000000d08c9ddf0115d1118c7a00c04fc297eb0100000000' } | ConvertTo-Json
            [System.IO.File]::WriteAllText($script:Record, $forged)
            { Import-AuthentikCredential -Path $script:Record } | Should-Throw -ExceptionMessage '*could not be decrypted*New-TestServiceApp -Force*'
        }
    }

    It 'refuses a record with a required field missing, and a missing record with the command to run' {
        InModuleScope TestEnvironment {
            { Import-AuthentikCredential -Path (Join-Path $TestDrive 'nowhere.json') } | Should-Throw -ExceptionMessage '*New-TestServiceApp*'

            [System.IO.File]::WriteAllText($script:Record, (@{ baseUrl = 'https://auth.example.com'; username = 'u' } | ConvertTo-Json))
            { Import-AuthentikCredential -Path $script:Record } | Should-Throw -ExceptionMessage "*'userPk'*"
        }
    }

    It 'warns when a record holds the token unprotected, and still returns it' {
        InModuleScope TestEnvironment {
            [System.IO.File]::WriteAllText($script:Record, (@{ baseUrl = 'https://auth.example.com'; username = 'u'; userPk = 1; protection = 'None'; tokenProtected = 'plain' } | ConvertTo-Json))
            $back = Import-AuthentikCredential -Path $script:Record -WarningVariable warnings -WarningAction SilentlyContinue
            $back.Token | Should-Be 'plain'
            @($warnings | Where-Object { $_ -like '*unprotected*' }).Count | Should-Be 1
        }
    }

    It 'names the record by the instance host under the user profile' {
        InModuleScope TestEnvironment {
            $path = Get-AuthentikCredentialPath -BaseUrl 'https://auth.example.com:9443/'
            $path | Should-MatchString '\.testenvironment'
            (Split-Path $path -Leaf) | Should-Be 'auth.example.com.serviceaccount.json'
            Get-AuthentikCredentialPath -BaseUrl 'https://auth.example.com' -Path 'C:\elsewhere\x.json' | Should-Be 'C:\elsewhere\x.json'
            { Get-AuthentikCredentialPath -BaseUrl 'not a url' } | Should-Throw
        }
    }
}
