#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one credential record every provider writes and reads. Pinned here once, so the
    per-provider suites can be about their own fields: the secret is never on disk readable where
    the platform can protect it, a vault pointer is written only after the vault is proven usable,
    the record is UTF-8 without a byte order mark, the folder and file are restricted to the
    current user, and a record that lies about its protection is refused rather than guessed at.
#>

# Evaluated at discovery, because -Skip is decided before any BeforeAll runs.
$script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Export-TestCredentialRecord and Import-TestCredentialRecord' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            # Every test starts from a profile with no record folder, whichever ran before it.
            $script:Record = Join-Path (Join-Path $Drive 'creds') 'example.record.json'
            Remove-Item -LiteralPath (Split-Path $script:Record -Parent) -Recurse -Force -ErrorAction SilentlyContinue
            $script:Fields = [ordered]@{ schemaVersion = 1; baseUrl = 'https://x.example.com'; username = 'svc' }
            $script:Vault = @{}
            $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $true } }
            Mock Set-TestVaultSecret { $script:Vault[$SecretName] = $PlainText }
            Mock Get-TestVaultSecret { $script:Vault[$SecretName] }
            $script:WriteRecord = {
                param([string]$Json)
                $null = New-Item -ItemType Directory -Path (Split-Path $script:Record -Parent) -Force
                [System.IO.File]::WriteAllText($script:Record, $Json)
            }
        }
    }

    It 'writes the public fields in order, never the secret as plaintext where the platform can protect it, and reads it back unchanged' {
        InModuleScope TestEnvironment {
            $written = Export-TestCredentialRecord -Path $script:Record -Record $script:Fields -Secret 'tok-Zoë-秘密' `
                -SecretField tokenProtected -SecretName 'Lab-x' -Confirm:$false -WarningAction SilentlyContinue

            $bytes = [System.IO.File]::ReadAllBytes($script:Record)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should-BeFalse
            $json = [System.Text.Encoding]::UTF8.GetString($bytes)
            $stored = $json | ConvertFrom-Json
            @($stored.PSObject.Properties.Name)[0..2] | Should-BeCollection @('schemaVersion', 'baseUrl', 'username')
            if ($script:OnWindows) {
                $written.Protection | Should-Be 'DPAPI'
                $json | Should-NotMatchString 'tok-Zo'
            }

            $read = Import-TestCredentialRecord -Path $script:Record -Required baseUrl, username -SecretField tokenProtected -WarningAction SilentlyContinue
            $read.Secret | Should-Be 'tok-Zoë-秘密'
            $read.Record.username | Should-Be 'svc'
            $read.Protection | Should-Be $written.Protection
        }
    }

    It 'stores only a vault pointer under -UseSecretStore and reads the secret from the vault' {
        InModuleScope TestEnvironment {
            $written = Export-TestCredentialRecord -Path $script:Record -Record $script:Fields -Secret 'tok' -SecretField tokenProtected `
                -SecretName 'Lab-x' -UseSecretStore -VaultName 'LabVault' -Confirm:$false

            $stored = [System.IO.File]::ReadAllText($script:Record) | ConvertFrom-Json
            $stored.protection | Should-Be 'SecretStore'
            $stored.vaultName | Should-Be 'LabVault'
            $stored.secretName | Should-Be 'Lab-x'
            $stored.PSObject.Properties.Name | Should-NotContainCollection 'tokenProtected'
            $script:Vault['Lab-x'] | Should-Be 'tok'
            $written.SecretName | Should-Be 'Lab-x'

            (Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected).Secret | Should-Be 'tok'
            Should-Invoke Get-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $VaultName -eq 'LabVault' -and $SecretName -eq 'Lab-x' }
        }
    }

    It 'refuses to write anything when the vault is not usable, so no record ever names a secret that was not stored' {
        InModuleScope TestEnvironment {
            Mock Initialize-TestSecretVault { [PSCustomObject]@{ Available = $false } }

            { Export-TestCredentialRecord -Path $script:Record -Record $script:Fields -Secret 'tok' -SecretField tokenProtected -SecretName 'Lab-x' -UseSecretStore -VaultName 'LabVault' -Confirm:$false } |
                Should-Throw -ExceptionMessage '*not usable*'
            Test-Path -LiteralPath $script:Record | Should-BeFalse
            Should-NotInvoke Set-TestVaultSecret
        }
    }

    It 'writes nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = Export-TestCredentialRecord -Path $script:Record -Record $script:Fields -Secret 'tok' -SecretField tokenProtected -SecretName 'Lab-x' -WhatIf
            Test-Path -LiteralPath $script:Record | Should-BeFalse
        }
    }

    It 'restricts the record and its folder to the current user' -Skip:(-not $script:OnWindows) {
        InModuleScope TestEnvironment {
            $null = Export-TestCredentialRecord -Path $script:Record -Record $script:Fields -Secret 'tok' -SecretField tokenProtected -SecretName 'Lab-x' -Confirm:$false

            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            foreach ($target in $script:Record, (Split-Path $script:Record -Parent)) {
                $acl = Get-Acl -LiteralPath $target
                $acl.AreAccessRulesProtected | Should-BeTrue
                $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
                @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) | Should-BeCollection @($me.Value)
            }
        }
    }

    Context 'A record is refused rather than guessed at' {

        It 'names the command to run when there is no record' {
            InModuleScope TestEnvironment {
                { Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected -MissingRecordMessage 'Run New-TestServiceApp first.' } |
                    Should-Throw -ExceptionMessage '*Run New-TestServiceApp first.*'
            }
        }

        It 'refuses a record missing a field the caller requires' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'https://x.example.com'; protection = 'None'; tokenProtected = 'plain' } | ConvertTo-Json)
                { Import-TestCredentialRecord -Path $script:Record -Required baseUrl, username -SecretField tokenProtected } |
                    Should-Throw -ExceptionMessage "*'username'*"
            }
        }

        It 'refuses a record that is not JSON' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord 'not json at all'
                { Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected } | Should-Throw -ExceptionMessage '*not valid JSON*'
            }
        }

        It 'refuses a vault pointer that names no vault or secret' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'x'; protection = 'SecretStore'; vaultName = 'LabVault' } | ConvertTo-Json)
                { Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected -SecretLabel key } |
                    Should-Throw -ExceptionMessage '*does not name the vault or secret*'
                Should-NotInvoke Get-TestVaultSecret
            }
        }

        It 'refuses a record marked protected that carries no protected value' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'x'; protection = 'DPAPI' } | ConvertTo-Json)
                { Import-TestCredentialRecord -Path $script:Record -SecretField privateJwkProtected -SecretLabel key } |
                    Should-Throw -ExceptionMessage '*no protected key*'
            }
        }

        It 'explains a record that another user or machine wrote rather than failing opaquely' -Skip:(-not $script:OnWindows) {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'x'; protection = 'DPAPI'; tokenProtected = '01000000d08c9ddf0115d1118c7a00c04fc297eb0100000000' } | ConvertTo-Json)
                { Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected } | Should-Throw -ExceptionMessage '*could not be decrypted*'
            }
        }

        It 'warns when the secret is stored unprotected, and still returns it' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'x'; protection = 'None'; tokenProtected = 'plain' } | ConvertTo-Json)
                $read = Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected -SecretLabel token -WarningVariable warnings -WarningAction SilentlyContinue
                $read.Secret | Should-Be 'plain'
                $read.Protection | Should-Be 'None'
                @($warnings | Where-Object { $_ -like '*token*unprotected*' }).Count | Should-Be 1
            }
        }

        It 'refuses a record that yields an empty secret' {
            InModuleScope TestEnvironment {
                & $script:WriteRecord (@{ baseUrl = 'x'; protection = 'None'; tokenProtected = '' } | ConvertTo-Json)
                { Import-TestCredentialRecord -Path $script:Record -SecretField tokenProtected -WarningAction SilentlyContinue } |
                    Should-Throw -ExceptionMessage '*yielded no secret*'
            }
        }
    }
}

Describe 'Get-TestCredentialRoot' -Tag 'Unit', 'Private' {

    It 'names the folder under the user profile, and every provider path helper builds on it' {
        InModuleScope TestEnvironment {
            $root = Get-TestCredentialRoot
            $root | Should-Be (Join-Path $HOME '.testenvironment')

            Get-AuthentikCredentialPath -BaseUrl 'https://auth.example.com' | Should-Be (Join-Path $root 'auth.example.com.serviceaccount.json')
            Get-FreeIPACredentialPath -BaseUrl 'https://ipa.example.com' | Should-Be (Join-Path $root 'ipa.example.com.freeipa.json')
            Get-PingOneCredentialPath -EnvironmentId 'env-1' | Should-Be (Join-Path $root 'env-1.pingone.secret')
            Get-TestCredentialPath -TenantId 'tenant-1' | Should-Be (Join-Path $root 'tenant-1.serviceapp.json')
        }
    }

    It 'returns a caller-supplied path unchanged' {
        InModuleScope TestEnvironment {
            Get-OktaCredentialPath -OrgUrl 'https://trial-1.okta.com' -Path 'C:\elsewhere\x.json' | Should-Be 'C:\elsewhere\x.json'
        }
    }
}
