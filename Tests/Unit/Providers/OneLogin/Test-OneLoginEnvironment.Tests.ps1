#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called and disagrees with the account when something came back wrong. So the account here is
    built from the module's own seed files by the rules the seed applies - names through
    Resolve-OneLoginSeedName, lifecycle through the provider's status and state tables, managers and
    groups by id, roles holding their people and apps, directory fields through
    Resolve-OneLoginDirectoryIdentity, policies on their groups, API servers answering with the
    scopes, claims and clients the data lists - and the verifier must pass against it. Then one
    thing at a time is broken, and each must be named: a missing person, a first name that came
    back decomposed, a person OneLogin quietly left unlicensed, a manager pointing at the wrong
    person, a group member gone, a role grant dropped, a policy setting changed, a policy moved off
    its group, an API granted to an app the data never names, a directory field edited, a lock run
    out. A person a mapping added to a role is not a fault, and is pinned as not one.

    Everything is mocked. The account is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\OneLogin\Data'
}

Describe 'Test-OneLoginEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' } }
            Mock Resolve-OneLoginSeedName {
                switch ($Kind) {
                    'Username' { ('ZZ-TEST-{0}' -f $Key).ToLowerInvariant() }
                    'Email' { ('ZZ-TEST-{0}@onelogin-lab.example.com' -f $Key).ToLowerInvariant() }
                    default { 'ZZ-TEST-{0}' -f $Key }
                }
            }

            $data = $DataPath
            $read = { param($file) @(Import-Csv -LiteralPath (Join-Path $data $file) -Encoding UTF8) }
            $userRows = @(& $read 'OneLoginUsers.csv')
            $roleRows = @(& $read 'OneLoginRoles.csv')
            $groupRows = @(& $read 'OneLoginGroups.csv')
            $appRows = @(& $read 'OneLoginApps.csv')

            $idOf = @{}
            $i = 1000
            foreach ($row in $userRows) { $i++; $idOf[$row.Key] = $i }
            $groupId = @{}; $n = 0
            foreach ($row in $groupRows) { $n++; $groupId[$row.Key] = 500 + $n }
            $appId = @{}; $n = 0
            foreach ($row in $appRows) { $n++; $appId[$row.Key] = 700 + $n }

            $roleDataName = @{}; foreach ($row in $roleRows) { $roleDataName[$row.Key] = $row.Name }
            $groupDataName = @{}; foreach ($row in $groupRows) { $groupDataName[$row.Key] = $row.Name }
            $connection = @{ Subdomain = 'contoso'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' }

            $users = [System.Collections.Generic.List[object]]::new()
            foreach ($row in $userRows) {
                $user = [PSCustomObject]@{
                    id              = $idOf[$row.Key]
                    username        = ('zz-test-{0}' -f $row.Key)
                    firstname       = $row.GivenName
                    lastname        = $row.Surname
                    status          = $script:OneLoginUserStatus[$row.Status]
                    state           = $script:OneLoginUserState[$row.State]
                    group_id        = $(if ($row.Group) { $groupId[$row.Group] } else { $null })
                    manager_user_id = $(if ($row.Manager) { $idOf[$row.Manager] } else { $null })
                    locked_until    = $(if ($row.Status -eq 'Locked') { (Get-Date).AddDays(364).ToUniversalTime().ToString('o') } else { $null })
                }
                $directory = Resolve-OneLoginDirectoryIdentity -Row $row -RoleNameByKey $roleDataName -GroupNameByKey $groupDataName -Connection $connection
                foreach ($name in $directory.Keys) { $user | Add-Member -NotePropertyName $name -NotePropertyValue $directory[$name] }
                $users.Add($user)
            }
            $roles = [System.Collections.Generic.List[object]]::new()
            $n = 0
            foreach ($row in $roleRows) {
                $n++
                $members = [System.Collections.Generic.List[object]]@($userRows | Where-Object { @($_.Roles -split ';') -contains $row.Key } | ForEach-Object { $idOf[$_.Key] })
                $grants = @($appRows | Where-Object { @($_.Roles -split ';') -contains $row.Key } | ForEach-Object { $appId[$_.Key] })
                $roles.Add([PSCustomObject]@{ id = 300 + $n; name = 'ZZ-TEST-{0}' -f $row.Name; users = $members; apps = $grants; Key = $row.Key })
            }

            # Policies, each on the groups the data gives it, with the data's settings as its detail.
            $policyRows = @(& $read 'OneLoginPolicies.csv')
            $policyOfGroup = @{}
            $script:PolicyDetail = @{}
            $n = 0
            $policies = foreach ($row in $policyRows) {
                $n++
                foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) { $policyOfGroup[$key] = 800 + $n }
                $script:PolicyDetail[[string](800 + $n)] = [PSCustomObject]@{
                    id = 800 + $n; minimum_password_length = [int]$row.MinimumPasswordLength; password_expiration_days = [int]$row.PasswordExpirationDays
                    passwords_remembered = [int]$row.PasswordsRemembered; maximum_invalid_login_attempts = [int]$row.MaximumInvalidLoginAttempts
                    lock_effective_minutes = [int]$row.LockEffectiveMinutes
                }
                [PSCustomObject]@{ id = 800 + $n; name = 'ZZ-TEST-{0}' -f $row.Name }
            }

            # API servers answering with exactly the scopes, claims and clients the data lists.
            $script:ApiPart = @{}
            $n = 0
            $apiServers = foreach ($row in (& $read 'OneLoginApiAuthorizations.csv')) {
                $n++
                $id = 900 + $n
                $script:ApiPart["$id/scopes"] = @(@($row.Scopes -split '\|' | Where-Object { $_ }) | ForEach-Object { [PSCustomObject]@{ value = ($_ -split '=', 2)[0] } })
                $script:ApiPart["$id/claims"] = @(@($row.Claims -split '\|' | Where-Object { $_ }) | ForEach-Object { [PSCustomObject]@{ name = ($_ -split '=', 2)[0] } })
                $script:ApiPart["$id/clients"] = @(@($row.Clients -split '\|' | Where-Object { $_ }) | ForEach-Object {
                        $appKey, $scopeList = $_ -split '=', 2
                        [PSCustomObject]@{ app_id = $appId[$appKey]; scopes = @(@($scopeList -split ' ' | Where-Object { $_ }) | ForEach-Object { [PSCustomObject]@{ value = $_ } }) }
                    })
                [PSCustomObject]@{ id = $id; name = 'ZZ-TEST-{0}' -f $row.Name }
            }

            $n = 0
            $script:Fixture = @{
                Attributes        = @(& $read 'OneLoginCustomAttributes.csv' | ForEach-Object { [PSCustomObject]@{ id = 1; shortname = $_.Shortname } })
                Users             = $users
                Roles             = $roles
                Groups            = @($groupRows | ForEach-Object { [PSCustomObject]@{ id = $groupId[$_.Key]; name = 'ZZ-TEST-{0}' -f $_.Name; policy_id = $policyOfGroup[$_.Key] } })
                Apps              = @($appRows | ForEach-Object { [PSCustomObject]@{ id = $appId[$_.Key]; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Mappings          = @(& $read 'OneLoginMappings.csv' | ForEach-Object { [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Policies          = @($policies)
                ApiAuthorizations = @($apiServers)
                AppRules          = @(& $read 'OneLoginAppRules.csv' | ForEach-Object { $n++; [PSCustomObject]@{ id = 1100 + $n; name = 'ZZ-TEST-{0}' -f $_.Name; AppId = $appId[$_.App] } })
                Hooks             = @(& $read 'OneLoginHooks.csv' | ForEach-Object { [PSCustomObject]@{ id = "hook-$($_.Key)"; type = $_.Type; disabled = $true } })
                SelfRegistration  = @(& $read 'OneLoginSelfRegistrations.csv' | ForEach-Object { [PSCustomObject]@{ id = 1200; name = 'ZZ-TEST-{0}' -f $_.Name } })
            }
            $script:IdOf = $idOf
            $script:AppId = $appId

            Mock Get-OneLoginSeededObject { @($script:Fixture[$Type]) }
            Mock Invoke-OneLoginRequest { throw "Unexpected request $Method $Path" }
            Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -match '^policies/\d+$' } { $script:PolicyDetail[($Path -split '/')[1]] }
            Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -match '^api_authorizations/\d+/(scopes|claims|clients)$' } { $script:ApiPart[$Path.Substring('api_authorizations/'.Length)] }
            Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'GET' -and $Path -match '^mfa/users/\d+/devices$' } { }
        }
    }

    It 'passes against an account that holds exactly what the data describes, and only reads' {
        InModuleScope TestEnvironment {
            $result = Test-OneLoginEnvironment -Quiet
            $result.Provider | Should-Be 'OneLogin'
            $result.Target | Should-Be 'contoso'
            @($result.Checks | Where-Object { $_.Passed -eq $false } | ForEach-Object Name) | Should-BeCollection -Count 0
            $result.Passed | Should-BeTrue
            ($result.Checks | Where-Object Name -eq 'Managers').Expected | Should-BeGreaterThan 250
            foreach ($name in 'Policies', 'API authorizations', 'App rules', 'Smart hooks', 'Self-registration', 'Group policies', 'Policy settings', 'API scopes', 'API clients', 'Directory fields') {
                @($result.Checks | Where-Object Name -eq $name) | Should-BeCollection -Count 1 -Because "the verifier judges $name"
            }
            Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }

    It 'names a changed policy setting, a policy moved off its group, a stray API client, an edited directory field and a lock run out' {
        InModuleScope TestEnvironment {
            $strict = $script:Fixture.Policies | Where-Object name -eq 'ZZ-TEST-Strict Office'
            $script:PolicyDetail[[string]$strict.id].minimum_password_length = 8
            ($script:Fixture.Groups | Where-Object name -eq 'ZZ-TEST-New York').policy_id = $null
            $orders = $script:Fixture.ApiAuthorizations | Where-Object name -eq 'ZZ-TEST-Orders API'
            $script:ApiPart["$($orders.id)/clients"] = @($script:ApiPart["$($orders.id)/clients"]) + [PSCustomObject]@{ app_id = $script:AppId['wiki-saml']; scopes = @([PSCustomObject]@{ value = 'orders:admin' }) }
            ($script:Fixture.Users | Where-Object username -eq 'zz-test-jnino').samaccountname = 'jnino'
            ($script:Fixture.Users | Where-Object username -eq 'zz-test-ofitzgerald').locked_until = (Get-Date).AddHours(2).ToUniversalTime().ToString('o')

            $checks = (Test-OneLoginEnvironment -SkipMembership -Quiet).Checks
            @(($checks | Where-Object Name -eq 'Policy settings').Missing) | Should-BeCollection @('strict-office: minimum_password_length is 8, should be 14')
            @(($checks | Where-Object Name -eq 'Group policies').Missing) | Should-BeCollection @('ZZ-TEST-New York <- ZZ-TEST-Strict Office')
            @(($checks | Where-Object Name -eq 'API clients').Unexpected) | Should-BeCollection @('ZZ-TEST-Orders API <- ZZ-TEST-Wiki SAML : orders:admin')
            @(($checks | Where-Object Name -eq 'Directory fields').Missing) | Should-BeCollection @("jnino: samaccountname 'jnino' should be 'zz-test-jnino'")
            @(($checks | Where-Object Name -eq 'User lifecycle').Missing)[0] | Should-MatchString '^ofitzgerald: locked until .*less than a day away$'
        }
    }

    It 'names a missing person, a decomposed first name, an unlicensed one and a wrong manager' {
        InModuleScope TestEnvironment {
            $users = $script:Fixture.Users
            $null = $users.Remove(($users | Where-Object username -eq 'zz-test-svcreporting'))
            $jose = $users | Where-Object username -eq 'zz-test-jnino'
            $decomposed = 'Jose' + [string][char]0x0301
            ($decomposed -eq $jose.firstname) | Should-BeTrue
            $jose.firstname = $decomposed
            ($users | Where-Object username -eq 'zz-test-zmueller').state = 3
            ($users | Where-Object username -eq 'zz-test-jweiss').manager_user_id = $script:IdOf['awhitfield']

            $checks = (Test-OneLoginEnvironment -Quiet).Checks
            @(($checks | Where-Object Name -eq 'Users').Missing) | Should-BeCollection @('zz-test-svcreporting')
            @(($checks | Where-Object Name -eq 'User names').Missing) | Should-BeCollection @("jnino: first name 'Jose$([char]0x0301)' should be 'Jos$([char]0xE9)'")
            @(($checks | Where-Object Name -eq 'User lifecycle').Missing) | Should-BeCollection @('zmueller: state 3 should be 1 (Approved)')
            @(($checks | Where-Object Name -eq 'Managers').Missing) | Should-BeCollection @('jweiss: manager is zz-test-awhitfield, should be zz-test-mbell')
        }
    }

    It 'names a group member gone and a role grant dropped, and forgives a person a mapping added' {
        InModuleScope TestEnvironment {
            ($script:Fixture.Users | Where-Object username -eq 'zz-test-iisik').group_id = $null
            $allStaff = $script:Fixture.Roles | Where-Object Key -eq 'all-staff'
            $null = $allStaff.users.Remove($script:IdOf['nsorensen'])
            $finance = $script:Fixture.Roles | Where-Object Key -eq 'finance'
            $finance.users.Add($script:IdOf['gpapadopoulos'])

            $checks = (Test-OneLoginEnvironment -Quiet).Checks
            @(($checks | Where-Object Name -eq 'Group membership').Missing) | Should-BeCollection @('ZZ-TEST-London <- zz-test-iisik')
            $roleCheck = $checks | Where-Object Name -eq 'Role memberships'
            @($roleCheck.Missing) | Should-BeCollection @('ZZ-TEST-All Staff <- zz-test-nsorensen')
            @($roleCheck.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'names a group the data never describes, and reads no role or app grants under -SkipMembership' {
        InModuleScope TestEnvironment {
            $script:Fixture.Groups = @($script:Fixture.Groups) + [PSCustomObject]@{ id = 999; name = 'ZZ-TEST-Stray' }
            $result = Test-OneLoginEnvironment -SkipMembership -Quiet
            @(($result.Checks | Where-Object Name -eq 'Groups').Unexpected) | Should-BeCollection @('ZZ-TEST-Stray')
            @($result.Checks | Where-Object { $_.Name -in 'Role memberships', 'App assignments' }) | Should-BeCollection -Count 0
            Should-NotInvoke Write-TestMessage
        }
    }
}
