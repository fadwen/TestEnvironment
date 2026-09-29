#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Saved app secrets: New-OneLoginApp -SaveAppSecret, Get-OneLoginAppCredential, and teardown.

    OneLogin shows an app's client secret once, when the app is created. By default the seed drops
    it. With -SaveAppSecret it keeps the secrets of the confidential clients it creates - the two
    that authenticate with one - through the shared record writer, and nothing else: not a public
    or native client's, not the SAML app's, never one for an app it did not create in this run.

    The point of the teardown half is that saved secrets do not build up: each record goes with its
    app, and a record whose app is no longer in the account goes too. It must not go while its app
    lives, must not go under -WhatIf, must not be read at all under -Keep Apps, and a file that is
    not one of this account's records - another account's, or one whose content disagrees with its
    name - is never touched.

    The records are written for real into TestDrive:, with the credential folder pointed there, so
    the round trip is the real writer and reader. Every OneLogin call is mocked.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Saved OneLogin app secrets' -Tag 'Unit', 'Private', 'Credential' {

    BeforeEach {
        $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root
        InModuleScope TestEnvironment -Parameters @{ Root = $root } {
            param($Root)
            $script:CredentialRoot = $Root
            Mock Get-TestCredentialRoot { $script:CredentialRoot }
            Mock Protect-TestFile { }
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' } }
            Mock Invoke-OneLoginRequest { throw "Escaped the mocks: $Method $Path" }
            Mock Write-TestMessage { }
            Mock Write-Host { }
        }
    }

    Context 'The record, written and read back' {

        It 'writes a record the reader lists and the credential command returns as a PSCredential, with no secret on the pipeline' {
            InModuleScope TestEnvironment {
                $secret = 'app-secret-' + [char]0xE9 + '-42'
                $null = Export-OneLoginAppSecret -Subdomain Contoso -AppId 4001 -AppKey expenses -AppName 'ZZ-TEST-Expenses Web' `
                    -ClientId 'client-4001' -ClientSecret $secret -Confirm:$false -WarningAction SilentlyContinue

                $path = Join-Path $script:CredentialRoot 'contoso.onelogin-app.4001.json'
                Test-Path -LiteralPath $path | Should-BeTrue
                if ($env:OS -eq 'Windows_NT') {
                    [IO.File]::ReadAllText($path).Contains($secret) | Should-BeFalse -Because 'on Windows the secret is DPAPI-protected'
                }

                $records = @(Get-OneLoginAppSecretRecord -Subdomain contoso)
                $records.Count | Should-Be 1
                $records[0].AppKey | Should-Be 'expenses'
                ($records[0].PSObject.Properties.Value -contains $secret) | Should-BeFalse

                $app = @(Get-OneLoginAppCredential -WarningAction SilentlyContinue)
                $app.Count | Should-Be 1
                $app[0].Credential.UserName | Should-Be 'client-4001'
                [string]::Equals($app[0].Credential.GetNetworkCredential().Password, $secret, [StringComparison]::Ordinal) | Should-BeTrue
                ($app[0] | Select-Object Key, Name, AppId, Subdomain, Protection | ConvertTo-Json) | Should-NotMatchString ([regex]::Escape($secret))
            }
        }

        It 'filters by key, and reads nothing for another account' {
            InModuleScope TestEnvironment {
                foreach ($entry in @(@{ Id = 1; Key = 'expenses' }, @{ Id = 2; Key = 'payroll' })) {
                    $null = Export-OneLoginAppSecret -Subdomain contoso -AppId $entry.Id -AppKey $entry.Key -AppName "ZZ-TEST-$($entry.Key)" `
                        -ClientId "c$($entry.Id)" -ClientSecret "s$($entry.Id)" -Confirm:$false -WarningAction SilentlyContinue
                }
                @(Get-OneLoginAppCredential -Key payroll -WarningAction SilentlyContinue).Key | Should-BeCollection @('payroll')
                @(Get-OneLoginAppCredential -Subdomain fabrikam) | Should-BeCollection -Count 0
            }
        }

        It 'ignores a file whose content names another app than its file name' {
            InModuleScope TestEnvironment {
                $null = Export-OneLoginAppSecret -Subdomain contoso -AppId 7 -AppKey expenses -AppName 'ZZ-TEST-Expenses Web' `
                    -ClientId c -ClientSecret s -Confirm:$false -WarningAction SilentlyContinue
                Rename-Item -LiteralPath (Join-Path $script:CredentialRoot 'contoso.onelogin-app.7.json') -NewName 'contoso.onelogin-app.8.json'
                @(Get-OneLoginAppSecretRecord -Subdomain contoso -WarningAction SilentlyContinue) | Should-BeCollection -Count 0
            }
        }

        It 'removes the record, and the vault secret it points to, only when ShouldProcess allows' {
            InModuleScope TestEnvironment {
                $null = Export-OneLoginAppSecret -Subdomain contoso -AppId 9 -AppKey expenses -AppName 'ZZ-TEST-Expenses Web' `
                    -ClientId c -ClientSecret s -Confirm:$false -WarningAction SilentlyContinue
                $record = @(Get-OneLoginAppSecretRecord -Subdomain contoso)[0]

                Remove-OneLoginAppSecret -Record $record -WhatIf | Should-BeFalse
                Test-Path -LiteralPath $record.Path | Should-BeTrue

                Mock Remove-TestVaultSecret { $true }
                $vaulted = [PSCustomObject]@{ Path = $record.Path; AppId = '9'; AppName = 'x'; Protection = 'SecretStore'; VaultName = 'OneLoginEnvironment'; SecretName = 'OneLoginEnvironment-contoso-app-9' }
                Remove-OneLoginAppSecret -Record $vaulted -Confirm:$false | Should-BeTrue
                Test-Path -LiteralPath $record.Path | Should-BeFalse
                Should-Invoke Remove-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $VaultName -eq 'OneLoginEnvironment' -and $SecretName -eq 'OneLoginEnvironment-contoso-app-9' }
            }
        }
    }

    Context 'New-OneLoginApp -SaveAppSecret' {

        BeforeEach {
            InModuleScope TestEnvironment {
                $script:Sent = [System.Collections.Generic.List[object]]::new()
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } { }
                $script:NextApp = 800
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'apps' } {
                    $script:NextApp++
                    [PSCustomObject]@{ id = $script:NextApp; name = $Body.name; sso = [PSCustomObject]@{ client_id = "cid-$script:NextApp"; client_secret = "secret-$script:NextApp" } }
                }
                Mock Export-OneLoginAppSecret { $script:Sent.Add([PSCustomObject]@{ AppKey = $AppKey; ClientId = $ClientId; ClientSecret = $ClientSecret; UseSecretStore = [bool]$UseSecretStore }) }
            }
        }

        It 'keeps nothing without the switch' {
            InModuleScope TestEnvironment {
                $result = New-OneLoginApp -PassThru -Confirm:$false
                Should-NotInvoke Export-OneLoginAppSecret
                $result.SecretsSaved | Should-Be 0
            }
        }

        It 'saves the two confidential clients only, from the create answer, and never returns a secret' {
            InModuleScope TestEnvironment {
                $result = New-OneLoginApp -SaveAppSecret -PassThru -Confirm:$false
                ($script:Sent.AppKey | Sort-Object) | Should-BeCollection @('expenses', 'payroll')
                foreach ($saved in $script:Sent) { $saved.ClientSecret | Should-MatchString '^secret-\d+$'; $saved.ClientId | Should-MatchString '^cid-\d+$' }
                $result.SecretsSaved | Should-Be 2
                ($result | ConvertTo-Json -Depth 6) | Should-NotMatchString 'secret-\d'
            }
        }

        It 'passes -UseSecretStore through' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginApp -Key expenses -SaveAppSecret -UseSecretStore -Confirm:$false
                $script:Sent[0].UseSecretStore | Should-BeTrue
            }
        }

        It 'says an app that already existed has no secret to save, and saves nothing for it' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } {
                    [PSCustomObject]@{ id = 55; name = 'ZZ-TEST-Expenses Web'; description = 'Seeded by TestEnvironment. Safe to delete. [ZZ-TEST-seed]' }
                }
                $result = New-OneLoginApp -Key expenses -SaveAppSecret -PassThru -Confirm:$false -WarningVariable warned -WarningAction SilentlyContinue
                Should-NotInvoke Export-OneLoginAppSecret
                @($result.SecretsUnavailable) | Should-BeCollection @('expenses')
                ($warned -join ' ') | Should-MatchString 'only when the app is created'
            }
        }

        It 'does not warn about an existing app whose secret is already saved' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } {
                    [PSCustomObject]@{ id = 55; name = 'ZZ-TEST-Expenses Web'; description = 'Seeded by TestEnvironment. Safe to delete. [ZZ-TEST-seed]' }
                }
                Mock Get-OneLoginAppSecretRecord { [PSCustomObject]@{ AppId = '55'; AppKey = 'expenses' } }
                $result = New-OneLoginApp -Key expenses -SaveAppSecret -PassThru -Confirm:$false -WarningVariable warned
                @($result.SecretsUnavailable) | Should-BeCollection -Count 0
                @($warned) | Should-BeCollection -Count 0
            }
        }

        It 'saves nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginApp -SaveAppSecret -WhatIf
                Should-NotInvoke Export-OneLoginAppSecret
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' }
            }
        }

        It 'is passed on by the orchestrator only when asked for' {
            InModuleScope TestEnvironment {
                foreach ($step in 'New-OneLoginCustomAttribute', 'New-OneLoginRole', 'New-OneLoginGroup', 'New-OneLoginPolicy', 'New-OneLoginAppRule',
                    'New-OneLoginApiAuthorization', 'New-OneLoginMapping', 'New-OneLoginSmartHook', 'New-OneLoginSelfRegistration', 'New-OneLoginUser', 'New-OneLoginMfaFactor') {
                    Mock $step { [PSCustomObject]@{ Errors = @() } }
                }
                Mock New-OneLoginApp { [PSCustomObject]@{ Errors = @() } }
                $null = New-OneLoginEnvironment -Confirm:$false
                Should-Invoke New-OneLoginApp -Times 1 -Exactly -ParameterFilter { -not $SaveAppSecret }
                $null = New-OneLoginEnvironment -SaveAppSecret -UseSecretStore -Confirm:$false
                Should-Invoke New-OneLoginApp -Times 1 -Exactly -ParameterFilter { $SaveAppSecret -and $UseSecretStore }
            }
        }
    }

    Context 'Teardown removes saved secrets with their apps' {

        BeforeEach {
            InModuleScope TestEnvironment {
                # Seeded app 50 is deleted; app 60 is somebody else's and stays in the account;
                # app 70 is already gone. Every app has a saved record, and another account has one too.
                foreach ($entry in @(@{ Id = 50; Sub = 'contoso' }, @{ Id = 60; Sub = 'contoso' }, @{ Id = 70; Sub = 'contoso' }, @{ Id = 50; Sub = 'fabrikam' })) {
                    $null = Export-OneLoginAppSecret -Subdomain $entry.Sub -AppId $entry.Id -AppKey expenses -AppName "app $($entry.Id)" `
                        -ClientId c -ClientSecret s -Confirm:$false -WarningAction SilentlyContinue
                }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Unproven } { }
                Mock Get-OneLoginSeededObject -ParameterFilter { -not $Unproven } {
                    if ($Type -eq 'Apps') { [PSCustomObject]@{ id = 50; name = 'ZZ-TEST-Expenses Web' } }
                }
                $script:AppDeleted = $false
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'DELETE' } { if ($Path -eq 'apps/50') { $script:AppDeleted = $true } }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } {
                    [PSCustomObject]@{ id = 60 }
                    if (-not $script:AppDeleted) { [PSCustomObject]@{ id = 50 } }
                }
                $script:Left = { @(Get-ChildItem -LiteralPath $script:CredentialRoot -Filter '*.onelogin-app.*.json' | ForEach-Object Name | Sort-Object) }
            }
        }

        It 'deletes the deleted app''s record and the orphan''s, and keeps the live app''s and the other account''s' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -PassThru
                $result.AppSecretsRemoved | Should-Be 2
                (& $script:Left) | Should-BeCollection @('contoso.onelogin-app.60.json', 'fabrikam.onelogin-app.50.json')
                $result.TotalRemoved | Should-Be 1 -Because 'a saved secret is not an object in the account'
            }
        }

        It 'deletes nothing under -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -WhatIf -PassThru
                $result.AppSecretsRemoved | Should-Be 0
                @(& $script:Left).Count | Should-Be 4
            }
        }

        It 'reads no saved secret at all under -Keep Apps' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginAppSecretRecord { throw 'Records must not be read when the apps are kept.' }
                $result = Remove-OneLoginEnvironment -Force -Keep Apps -PassThru
                $result.AppSecretsRemoved | Should-Be 0
                @(& $script:Left).Count | Should-Be 4
            }
        }

        It 'leaves the orphans when the account''s apps cannot be listed, and says so' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } { throw 'HTTP 503' }
                $result = Remove-OneLoginEnvironment -Force -PassThru -WarningAction SilentlyContinue
                $result.AppSecretsRemoved | Should-Be 1
                $left = & $script:Left
                ($left -contains 'contoso.onelogin-app.70.json') | Should-BeTrue -Because 'the orphan cannot be told from a live app without the listing'
                ($left -contains 'contoso.onelogin-app.60.json') | Should-BeTrue
                @($result.Errors | Where-Object { $_ -like '*Could not list the account''s apps*' }) | Should-BeCollection -Count 1
            }
        }
    }
}
