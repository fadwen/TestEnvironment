#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The seed steps, and the safety properties that have no parameter.

    - Every mapping carries the seed-tag condition with match all, whatever the data says, so an
      enabled one can act on seeded people and nobody else. No switch leaves it out.
    - Nobody who is not seeded is ever sent anywhere: the users step adds to roles and names as
      managers only ids it created or proved, and the roles, apps and mappings steps use only roles
      that are empty or hold seeded people alone. A prefixed role holding somebody else is left
      alone and said so.
    - An app's client secret, which OneLogin returns on create, is not kept unless -SaveAppSecret asks;
      OneLoginAppSecret.Tests.ps1 covers the switch.
    - A role grant goes out as a JSON array even for one id; ConvertTo-Json would have sent the
      bare number.
    - A person OneLogin quietly left unlicensed is reported by the seed, not only by verification.

    Every call is mocked. This suite must never reach an account.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'The OneLogin seed steps' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' } }
            Mock Invoke-OneLoginRequest { throw "Escaped the mocks: $Method $Path" }
            Mock Write-TestProgress { }
            # Never the real credential folder.
            Mock Get-OneLoginAppSecretRecord { }
            Mock Export-OneLoginAppSecret { throw 'An app secret must not be saved without -SaveAppSecret.' }
            $script:Sent = [System.Collections.Generic.List[object]]::new()
        }
    }

    Context 'New-OneLoginMapping' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } {
                    [PSCustomObject]@{ id = 31; name = 'ZZ-TEST-Finance' }
                    [PSCustomObject]@{ id = 32; name = 'ZZ-TEST-Engineering' }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'mappings' } { , @() }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'mappings' } { $script:Sent.Add($Body); [PSCustomObject]@{ id = 1 } }
            }
        }

        It 'gates every mapping on the seed tag with match all, and adds only a role' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginMapping -Confirm:$false
                $script:Sent.Count | Should-Be 2
                foreach ($body in $script:Sent) {
                    $body.match | Should-Be 'all'
                    @($body.conditions | Where-Object { $_.source -ceq 'custom_attribute_zztest_seed_tag' -and $_.operator -eq '=' -and $_.value -ceq 'ZZ-TEST-seed' }) | Should-BeCollection -Count 1
                    @($body.actions | ForEach-Object action) | Should-BeCollection @('add_role')
                }
                ($script:Sent | Where-Object { $_.enabled }).actions[0].value | Should-BeCollection @('31')
            }
        }

        It 'has no parameter that could leave the gate out or widen the match' {
            InModuleScope TestEnvironment {
                @((Get-Command New-OneLoginMapping).Parameters.Keys | Where-Object { $_ -match 'Gate|Match|Condition|Ungated' }) | Should-BeCollection -Count 0
            }
        }

        It 'refuses to reuse a prefixed mapping someone made without the gate' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'mappings' -and -not $Query } {
                    , @([PSCustomObject]@{ id = 9; name = 'ZZ-TEST-Finance department gets Finance'; match = 'all'; enabled = $true; conditions = @([PSCustomObject]@{ source = 'department'; operator = '='; value = 'Finance' }) })
                }
                $result = New-OneLoginMapping -Key finance-dept -PassThru -Confirm:$false
                $result.Errors[0] | Should-MatchString 'without the seed-tag condition'
                $script:Sent | Should-BeCollection -Count 0
            }
        }
    }

    Context 'New-OneLoginUser' {

        BeforeEach {
            InModuleScope TestEnvironment {
                $script:NextId = 5000
                # One person already seeded, exactly as the data describes her; nothing else in the
                # account is ours.
                $data = Get-OneLoginDataPath
                $roleNames = @{}; foreach ($row in (Import-Csv (Join-Path $data 'OneLoginRoles.csv') -Encoding UTF8)) { $roleNames[$row.Key] = $row.Name }
                $groupNames = @{}; foreach ($row in (Import-Csv (Join-Path $data 'OneLoginGroups.csv') -Encoding UTF8)) { $groupNames[$row.Key] = $row.Name }
                $adaRow = Import-Csv (Join-Path $data 'OneLoginUsers.csv') -Encoding UTF8 | Where-Object Key -eq 'awhitfield'
                $script:AdaDirectory = Resolve-OneLoginDirectoryIdentity -Row $adaRow -RoleNameByKey $roleNames -GroupNameByKey $groupNames `
                    -Connection @{ Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' }
                $script:NewAda = {
                    param([int]$Status)
                    $ada = [PSCustomObject]@{ id = 4001; username = 'zz-test-awhitfield'; firstname = 'Ada'; lastname = 'Whitfield'; title = 'Chief Executive'; department = 'Executive'; company = $null
                        status = $Status; state = 1; group_id = 610; manager_user_id = $null
                        custom_attributes = [PSCustomObject]@{ zztest_seed_tag = 'ZZ-TEST-seed'; zztest_badge_id = 'B-1001'; zztest_contractor = 'false'; zztest_cost_center = 'CC-100' } }
                    foreach ($name in $script:AdaDirectory.Keys) { $ada | Add-Member -NotePropertyName $name -NotePropertyValue $script:AdaDirectory[$name] }
                    $ada
                }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } { & $script:NewAda 1 }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Groups' } {
                    foreach ($name in 'Seattle HQ', 'London', 'New York', 'US Regional Offices', 'Remote Workers') { [PSCustomObject]@{ id = 600 + $name.Length; name = "ZZ-TEST-$name" } }
                }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } {
                    [PSCustomObject]@{ id = 31; name = 'ZZ-TEST-All Staff'; users = @(4001) }
                    [PSCustomObject]@{ id = 32; name = 'ZZ-TEST-Engineering'; users = @() }
                    [PSCustomObject]@{ id = 33; name = 'ZZ-TEST-Finance'; users = @() }
                    [PSCustomObject]@{ id = 34; name = 'ZZ-TEST-Contractors'; users = @() }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'users' } {
                    $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body })
                    $script:NextId++
                    [PSCustomObject]@{ id = $script:NextId }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -in 'POST', 'PUT' -and $Path -ne 'users' } {
                    $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body })
                }
                # The read-back after granting: by default OneLogin shows every grant already sent.
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } {
                    foreach ($roleId in 31, 32, 33, 34) {
                        $ids = foreach ($grant in @($script:Sent | Where-Object Path -eq "roles/$roleId/users")) { $parsed = $grant.Body | ConvertFrom-Json; @($parsed) }
                        [PSCustomObject]@{ id = $roleId; users = @($ids) }
                    }
                }
                Mock Start-Sleep { }
            }
        }

        It 'waits until OneLogin shows every grant it sent, and says so if it never does' {
            InModuleScope TestEnvironment {
                $script:Reads = 0
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } {
                    $script:Reads++
                    if ($script:Reads -lt 3) { return }
                    foreach ($roleId in 31, 32, 33, 34) {
                        $ids = foreach ($grant in @($script:Sent | Where-Object Path -eq "roles/$roleId/users")) { $parsed = $grant.Body | ConvertFrom-Json; @($parsed) }
                        [PSCustomObject]@{ id = $roleId; users = @($ids) }
                    }
                }
                $settled = New-OneLoginUser -Tier Core -PassThru -Confirm:$false
                $settled.GrantsNotYetShown | Should-Be 0
                Should-Invoke Start-Sleep -Times 2 -Exactly

                $script:Sent.Clear()
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } { }
                $pending = New-OneLoginUser -Tier Core -PassThru -Confirm:$false -WarningVariable warned -WarningAction SilentlyContinue
                $pending.GrantsNotYetShown | Should-BeGreaterThan 0
                @($warned | Where-Object { "$_" -like 'OneLogin has not yet shown*' }) | Should-BeCollection -Count 1
            }
        }

        It 'sends a grant OneLogin answered and never applied again, and stops waiting once it shows' {
            # Found live: on some runs OneLogin answers a role grant 200 and applies nothing, and a
            # grant sent again is applied. Here the first grants are ignored and only the re-sent
            # ones count.
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } {
                    foreach ($roleId in 31, 32, 33, 34) {
                        $sends = @($script:Sent | Where-Object Path -eq "roles/$roleId/users")
                        $ids = foreach ($grant in @($sends | Select-Object -Skip 1)) { $parsed = $grant.Body | ConvertFrom-Json; @($parsed) }
                        [PSCustomObject]@{ id = $roleId; users = @($ids) }
                    }
                }
                $result = New-OneLoginUser -Tier Core -PassThru -Confirm:$false -WarningAction SilentlyContinue
                $result.GrantsNotYetShown | Should-Be 0
                foreach ($roleId in 31, 32, 33, 34) {
                    @($script:Sent | Where-Object Path -eq "roles/$roleId/users").Count | Should-Be 2
                }
                Should-Invoke Start-Sleep -Times 6 -Exactly
            }
        }

        It 'sends only ids it created or proved, to roles and as managers' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginUser -Tier Core -Confirm:$false
                $known = @(4001) + @(5001..($script:NextId))
                $created = @($script:Sent | Where-Object Path -eq 'users')
                @($created | Where-Object { $_.Body.manager_user_id -and $known -notcontains [int]$_.Body.manager_user_id }) | Should-BeCollection -Count 0
                foreach ($grant in @($script:Sent | Where-Object Path -like 'roles/*/users')) {
                    # Assigned before it is wrapped: Windows PowerShell's ConvertFrom-Json emits a
                    # JSON array as one object, so @(... | ConvertFrom-Json) nests it there.
                    $parsed = $grant.Body | ConvertFrom-Json
                    $ids = @($parsed)
                    @($ids | Where-Object { $known -notcontains [int]$_ }) | Should-BeCollection -Count 0
                }
            }
        }

        It 'sends role grants as a JSON array, one request per role, and never re-adds a member' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginUser -Tier Core -Confirm:$false
                $grants = @($script:Sent | Where-Object Path -like 'roles/*/users')
                ($grants.Path | Sort-Object) | Should-BeCollection @('roles/31/users', 'roles/32/users', 'roles/33/users', 'roles/34/users')
                foreach ($grant in $grants) { $grant.Body | Should-MatchString '^\[\d+(,\d+)*\]$' }
                ($grants | Where-Object Path -eq 'roles/31/users').Body | Should-NotMatchString '4001'
                ($grants | Where-Object Path -eq 'roles/33/users').Body | Should-MatchString '^\[\d+\]$'
            }
        }

        It 'writes the seed tag, the lifecycle and the group on each person it creates, and reuses the one already seeded' {
            InModuleScope TestEnvironment {
                $result = New-OneLoginUser -Username awhitfield, jnino, mbell -PassThru -Confirm:$false
                $result.ReusedUsers | Should-Be 1
                $created = @($script:Sent | Where-Object Path -eq 'users')
                $created.Count | Should-Be 2
                foreach ($request in $created) { $request.Body.custom_attributes.zztest_seed_tag | Should-Be 'ZZ-TEST-seed' }
                $mbell = ($created | Where-Object { $_.Body.username -eq 'zz-test-mbell' }).Body
                $mbell.status | Should-Be 2
                $mbell.state | Should-Be 1
                $mbell.manager_user_id | Should-Be 4001
                $mbell.custom_attributes.zztest_contractor | Should-Be 'false'
            }
        }

        It 'puts a reused person back as the data describes, sending only what differs' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } { & $script:NewAda 2 }
                $result = New-OneLoginUser -Username awhitfield -PassThru -Confirm:$false
                $result.UpdatedUsers | Should-Be 1
                $update = @($script:Sent | Where-Object Path -eq 'users/4001')
                $update.Count | Should-Be 1
                @($update[0].Body.Keys) | Should-BeCollection @('status')
                $update[0].Body.status | Should-Be 1
            }
        }

        It 'builds every directory identifier inside the seed''s namespace, so none can match a real account' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginUser -Tier Core -Confirm:$false
                $created = @($script:Sent | Where-Object Path -eq 'users' | ForEach-Object Body)
                $created.Count | Should-BeGreaterThan 0
                foreach ($body in $created) {
                    $body.samaccountname | Should-MatchString '^zz-test-'
                    $body.samaccountname.Length | Should-BeLessThanOrEqual 20
                    $body.userprincipalname | Should-MatchString '@onelogin-lab\.example\.com$'
                    $body.distinguished_name | Should-MatchString ',OU=ZZ-TEST-Users,DC=onelogin-lab,DC=example,DC=com$'
                    foreach ($dn in @($body.member_of -split ';' | Where-Object { $_ })) { $dn | Should-MatchString '^CN=ZZ-TEST-.*,OU=ZZ-TEST-Groups,DC=onelogin-lab,DC=example,DC=com$' }
                    $body.external_id | Should-MatchString '^ZZ-TEST-'
                    $body.comment | Should-MatchString '\[ZZ-TEST-seed\]'
                }
                # The display name is the common name, escaped: the ideographic space survives.
                ($created | Where-Object username -eq 'zz-test-jjiang').distinguished_name.IndexOf([char]0x3000) | Should-BeGreaterThan 0
            }
        }

        It 'locks the Locked person through the lock call for a year, and never sends a status of 3' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginUser -Tier Core -Confirm:$false
                $ofitz = ($script:Sent | Where-Object { $_.Path -eq 'users' -and $_.Body.username -eq 'zz-test-ofitzgerald' }).Body
                $ofitz.status | Should-Be 1
                @($script:Sent | Where-Object { $_.Body.status -eq 3 }) | Should-BeCollection -Count 0
                $lock = @($script:Sent | Where-Object Path -like '/api/1/users/*/lock_user')
                $lock.Count | Should-Be 1
                $lock[0].Body.locked_until | Should-Be 525600
            }
        }

        It 'locks again only when the lock is missing or has less than a month left' {
            InModuleScope TestEnvironment {
                $script:Until = (Get-Date).AddDays(200)
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } {
                    [PSCustomObject]@{ id = 4008; username = 'zz-test-ofitzgerald'; status = 3; state = 1; locked_until = $script:Until.ToString('o') }
                }
                $null = New-OneLoginUser -Username ofitzgerald -Confirm:$false
                @($script:Sent | Where-Object Path -like '/api/1/users/*/lock_user') | Should-BeCollection -Count 0

                $script:Sent.Clear()
                $script:Until = (Get-Date).AddDays(3)
                $null = New-OneLoginUser -Username ofitzgerald -Confirm:$false
                @($script:Sent | Where-Object Path -eq '/api/1/users/4008/lock_user') | Should-BeCollection -Count 1
            }
        }

        It 'says when OneLogin left a person it was asked to approve unlicensed' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } {
                    if ($script:Sent.Count -gt 0) {
                        [PSCustomObject]@{ id = 5001; username = 'zz-test-jnino'; status = 1; state = 3 }
                    }
                }
                $result = New-OneLoginUser -Username jnino -PassThru -Confirm:$false
                @($result.Errors | Where-Object { $_ -like '1 person(s) the data approves were made Unlicensed*zz-test-jnino*' }) | Should-BeCollection -Count 1
            }
        }

        It 'creates and grants nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                $null = New-OneLoginUser -Tier Core -WhatIf
                $script:Sent | Should-BeCollection -Count 0
            }
        }
    }

    Context 'The steps that could reach out of the seed, and do not' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } { [PSCustomObject]@{ id = 4001; username = 'zz-test-awhitfield' } }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } {
                    [PSCustomObject]@{ id = 31; name = 'ZZ-TEST-All Staff' }
                    [PSCustomObject]@{ id = 32; name = 'ZZ-TEST-Engineering' }
                    [PSCustomObject]@{ id = 33; name = 'ZZ-TEST-Finance' }
                    [PSCustomObject]@{ id = 34; name = 'ZZ-TEST-Contractors' }
                }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Apps' } {
                    foreach ($name in 'Expenses Web', 'Payroll Console', 'Contractor Portal SPA', 'Field App', 'Wiki SAML') { [PSCustomObject]@{ id = 700 + $name.Length; name = "ZZ-TEST-$name" } }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -in 'POST', 'PUT' } { $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body; Method = $Method }); [PSCustomObject]@{ id = 99 } }
            }
        }

        It 'attaches a policy only to groups the seed may use, never makes it the default, and leaves a real group alone' {
            InModuleScope TestEnvironment {
                # Seattle HQ is the seed's; New York has somebody else in it, so it is not offered.
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Groups' } { [PSCustomObject]@{ id = 610; name = 'ZZ-TEST-Seattle HQ'; policy_id = $null } }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Policies' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'policies' } { , @([PSCustomObject]@{ id = 1; name = 'Default policy'; is_default = $true }) }
                $result = New-OneLoginPolicy -Key strict-office -PassThru -Confirm:$false
                $created = @($script:Sent | Where-Object Path -eq 'policies')
                $created.Count | Should-Be 1
                $created[0].Body.Keys | Should-NotContainCollection 'is_default'
                $created[0].Body.minimum_password_length | Should-Be 14
                @($script:Sent | Where-Object Path -like 'groups/*').Path | Should-BeCollection @('groups/610')
                @($result.Errors | Where-Object { $_ -like '*New York*' -or $_ -like "*new-york*" }) | Should-BeCollection -Count 1
            }
        }

        It 'refuses a same-named policy it cannot prove, and attaches it to nothing' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Groups' } { [PSCustomObject]@{ id = 610; name = 'ZZ-TEST-Seattle HQ' } }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Policies' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'policies' } { , @([PSCustomObject]@{ id = 5; name = 'ZZ-TEST-Strict Office'; is_default = $false }) }
                $result = New-OneLoginPolicy -Key strict-office -PassThru -Confirm:$false
                $result.Errors[0] | Should-MatchString 'left alone'
                $script:Sent | Should-BeCollection -Count 0
            }
        }

        It 'lets only seeded apps ask for an API, and tags the server' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -like 'api_authorizations/*/scopes' } {
                    $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body }); [PSCustomObject]@{ id = 900 + $script:Sent.Count }
                }
                $null = New-OneLoginApiAuthorization -Confirm:$false
                foreach ($server in @($script:Sent | Where-Object Path -eq 'api_authorizations')) {
                    $server.Body.description | Should-MatchString '\[ZZ-TEST-seed\]'
                    $server.Body.configuration.resource_identifier | Should-MatchString '^https://api\.onelogin-lab\.example\.com/'
                }
                $appIds = foreach ($name in 'Expenses Web', 'Payroll Console', 'Contractor Portal SPA', 'Field App', 'Wiki SAML') { 700 + $name.Length }
                $clients = @($script:Sent | Where-Object Path -like 'api_authorizations/*/clients')
                $clients.Count | Should-Be 3
                @($clients | Where-Object { $appIds -notcontains [int]$_.Body.app_id }) | Should-BeCollection -Count 0
            }
        }

        It 'puts app rules only on seeded apps, naming seeded roles, with the provider''s own action' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' } { }
                $null = New-OneLoginAppRule -Confirm:$false
                $rules = @($script:Sent | Where-Object Path -like 'apps/*/rules')
                $rules.Count | Should-Be 2
                foreach ($rule in $rules) {
                    (@('31', '33') -contains [string]$rule.Body.conditions[0].value) | Should-BeTrue
                    $rule.Body.actions[0].action | Should-Be 'set_groups'
                    @($rule.Body.actions[0].value) | Should-BeCollection @('member_of')
                }
            }
        }

        It 'creates the hook disabled, gated on a seeded role, with the marker as its first line' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Hooks' } { }
                $null = New-OneLoginSmartHook -Confirm:$false
                $hook = @($script:Sent | Where-Object Path -eq 'hooks')
                $hook.Count | Should-Be 1
                $hook[0].Body.disabled | Should-BeTrue
                @($hook[0].Body.conditions) | Should-BeCollection -Count 1
                $hook[0].Body.conditions[0].value | Should-Be '34'
                $code = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($hook[0].Body.function))
                $code | Should-MatchString '^// Seeded by TestEnvironment\. Safe to delete\. \[ZZ-TEST-seed\]'
            }
        }

        It 'turns its own hook off again if somebody enabled it' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Hooks' } { [PSCustomObject]@{ id = 'h1'; type = 'pre-authentication'; disabled = $false; name = 'pre-authentication hook h1' } }
                $result = New-OneLoginSmartHook -PassThru -Confirm:$false
                $result.DisabledAgain | Should-Be 1
                ($script:Sent | Where-Object Path -eq 'hooks/h1').Body.disabled | Should-BeTrue
                @($script:Sent | Where-Object Path -eq 'hooks') | Should-BeCollection -Count 0
            }
        }

        It 'creates the sign-up profile disabled, moderated, lab-domain only and with no default role or group, and puts that back' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'self_registration_profiles' } { [PSCustomObject]@{ self_registration_profiles = @() } }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'SelfRegistration' } { }
                $null = New-OneLoginSelfRegistration -Confirm:$false
                $profileBody = ($script:Sent | Where-Object Path -eq 'self_registration_profiles').Body.self_registration_profile
                $profileBody.enabled | Should-BeFalse
                $profileBody.moderated | Should-BeTrue
                $profileBody.domain_whitelist | Should-Be 'onelogin-lab.example.com'
                $profileBody.default_role_id | Should-BeNull
                $profileBody.default_group_id | Should-BeNull

                $script:Sent.Clear()
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'self_registration_profiles' } { [PSCustomObject]@{ self_registration_profiles = @([PSCustomObject]@{ id = 8; name = 'ZZ-TEST-Partner Sign-up' }) } }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'SelfRegistration' } { [PSCustomObject]@{ id = 8; name = 'ZZ-TEST-Partner Sign-up'; enabled = $true; moderated = $true; domain_whitelist = 'onelogin-lab.example.com' } }
                $restored = New-OneLoginSelfRegistration -PassThru -Confirm:$false
                $restored.Restored | Should-Be 1
                ($script:Sent | Where-Object Path -eq 'self_registration_profiles/8').Body.self_registration_profile.enabled | Should-BeFalse
            }
        }

        It 'enrols an MFA factor only where the account offers it, only verified, and only on seeded people' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Users' } {
                    foreach ($key in 'awhitfield', 'praghunathan', 'talvarez') { [PSCustomObject]@{ id = 4000 + $key.Length; username = "zz-test-$key" } }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -like 'mfa/users/*/devices' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -like 'mfa/users/*/factors' } { }
                $skipped = New-OneLoginMfaFactor -PassThru -Confirm:$false
                @($skipped.Skipped).Count | Should-Be 3
                @($skipped.Errors) | Should-BeCollection -Count 0
                $script:Sent | Should-BeCollection -Count 0

                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -like 'mfa/users/*/factors' } { , @([PSCustomObject]@{ factor_id = 77; name = 'Email'; auth_factor_name = 'OneLogin Email' }) }
                $enrolled = New-OneLoginMfaFactor -PassThru -Confirm:$false
                $enrolled.EnrolledFactors | Should-Be 3
                foreach ($request in @($script:Sent | Where-Object Path -like 'mfa/users/*/registrations')) {
                    $request.Body.verified | Should-BeTrue
                    $request.Body.factor_id | Should-Be 77
                }
            }
        }

        It 'has no parameter on any step that could loosen what keeps the seed in' {
            InModuleScope TestEnvironment {
                foreach ($command in 'New-OneLoginPolicy', 'New-OneLoginApiAuthorization', 'New-OneLoginAppRule', 'New-OneLoginSmartHook', 'New-OneLoginSelfRegistration', 'New-OneLoginMfaFactor', 'New-OneLoginMapping', 'New-OneLoginUser') {
                    @((Get-Command $command).Parameters.Keys | Where-Object { $_ -match 'Enable|Disable|Default|Moderat|Domain|Gate|Condition|Admin|Verified|Group$|Role$' }) |
                        Should-BeCollection -Count 0 -Because "$command must not be able to reach beyond the seed"
                }
            }
        }
    }

    Context 'New-OneLoginRole and New-OneLoginApp' {

        It 'leaves a prefixed role that holds somebody else alone, and creates the rest' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } {
                    [PSCustomObject]@{ id = 31; name = 'ZZ-TEST-All Staff'; users = @(900000001) }
                }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'roles' } { $script:Sent.Add($Body.name); [PSCustomObject]@{ id = 40 } }

                $result = New-OneLoginRole -PassThru -Confirm:$false
                $result.Errors[0] | Should-MatchString "'ZZ-TEST-All Staff' already exists and holds"
                $script:Sent | Should-NotContainCollection 'ZZ-TEST-All Staff'
                $script:Sent.Count | Should-Be 3
            }
        }

        It 'names the trial''s limit when OneLogin refuses a role for the plan' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'roles' } { }
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'roles' } {
                    throw 'OneLogin POST roles failed with HTTP 422: Your current plan max role limit is exceed can not create more roles.'
                }
                $result = New-OneLoginRole -Key finance -PassThru -Confirm:$false -WarningAction SilentlyContinue
                $result.Errors[0] | Should-MatchString 'a OneLogin trial allows five, the Default role among them'
            }
        }

        It 'keeps no client secret, gives a public client PKCE, and grants apps to seeded roles as one JSON array per role' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } {
                    [PSCustomObject]@{ id = 31; name = 'ZZ-TEST-All Staff' }
                    [PSCustomObject]@{ id = 33; name = 'ZZ-TEST-Finance' }
                    [PSCustomObject]@{ id = 34; name = 'ZZ-TEST-Contractors' }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -like 'roles/*/apps' } { }
                $script:NextApp = 800
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'apps' } {
                    $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body })
                    $script:NextApp++
                    [PSCustomObject]@{ id = $script:NextApp; sso = [PSCustomObject]@{ client_id = 'cid'; client_secret = 'do-not-keep-me' } }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'PUT' -and $Path -like 'roles/*/apps' } { $script:Sent.Add([PSCustomObject]@{ Path = $Path; Body = $Body }) }

                $result = New-OneLoginApp -PassThru -Confirm:$false
                ($result | ConvertTo-Json -Depth 6) | Should-NotMatchString 'do-not-keep-me'

                $apps = @($script:Sent | Where-Object Path -eq 'apps' | ForEach-Object Body)
                foreach ($app in $apps) { $app.description | Should-MatchString '\[ZZ-TEST-seed\]' }
                @($apps | Where-Object { $_.connector_id -eq 108419 -and $_.configuration.token_endpoint_auth_method -eq 2 }).Count | Should-BeGreaterThan 0
                @($apps | ForEach-Object { $_.configuration.redirect_uri; $_.configuration.consumer_url } | Where-Object { $_ -like 'http*' -and $_ -notlike '*onelogin-lab.example.com*' }) |
                    Should-BeCollection -Count 0

                $grants = @($script:Sent | Where-Object Path -like 'roles/*/apps')
                ($grants.Path | Sort-Object) | Should-BeCollection @('roles/31/apps', 'roles/33/apps', 'roles/34/apps')
                foreach ($grant in $grants) { $grant.Body | Should-MatchString '^\[\d+(,\d+)*\]$' }
            }
        }

        It 'refuses to reuse a prefixed app without the seed tag' {
            InModuleScope TestEnvironment {
                Mock Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' } { }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'apps' } { [PSCustomObject]@{ id = 9; name = 'ZZ-TEST-Expenses Web'; description = 'Ours, really' } }
                $result = New-OneLoginApp -Key expenses -PassThru -Confirm:$false
                $result.Errors[0] | Should-MatchString 'without the seed tag'
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -in 'POST', 'PUT' }
            }
        }
    }
}
