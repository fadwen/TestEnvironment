#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the OneLogin provider's seed data.

    A shifted CSV column is a data defect, not a logic one, and it is silent. More than that, most
    of what is pinned here is something OneLogin itself does without an error, each verified against
    a live trial account before it was written down:

    - it accepts a role grant for anyone and keeps it only for an approved person whose status is
      Active, Suspended, Locked, PasswordExpired or AwaitingPasswordReset;
    - it keeps a rejected person out of a group as it keeps her out of a role;
    - it approves a person only while the account has a licence for them, and a trial has twelve;
    - it turns Unactivated into PasswordPending and Unapproved into Approved, and it locks only a
      licensed person;
    - it allows a trial five roles, the Default role among them, and five apps.

    Data that asked for any of those would seed without an error and then fail verification, so the
    data is held to them here, at commit time. So is the isolation the provider promises: nothing
    in the data can name a real directory identity, a group outside the seed, or a real host.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    $script:DataPath = Join-Path $script:ModuleRoot 'Providers\OneLogin\Data'

    $read = { param($name) @(Import-Csv -LiteralPath (Join-Path $script:DataPath "$name.csv") -Encoding UTF8) }
    $script:Attributes = @(& $read 'OneLoginCustomAttributes')
    $script:Roles = @(& $read 'OneLoginRoles')
    $script:Groups = @(& $read 'OneLoginGroups')
    $script:Apps = @(& $read 'OneLoginApps')
    $script:Mappings = @(& $read 'OneLoginMappings')
    $script:Users = @(& $read 'OneLoginUsers')
    $script:Policies = @(& $read 'OneLoginPolicies')
    $script:ApiAuthorizations = @(& $read 'OneLoginApiAuthorizations')
    $script:AppRules = @(& $read 'OneLoginAppRules')
    $script:Hooks = @(& $read 'OneLoginHooks')
    $script:SelfRegistrations = @(& $read 'OneLoginSelfRegistrations')

    $script:Split = { param($value) @(([string]$value -split ';') | Where-Object { $_ }) }
    $script:CanHoldRole = { param($user) $user.State -eq 'Approved' -and $user.Status -in 'Active', 'Suspended', 'Locked', 'PasswordExpired', 'AwaitingPasswordReset' }
}

Describe 'OneLogin seed data' -Tag 'Unit', 'Contract' {

    Context 'Shape' {

        It 'ships every file with rows, and a purpose and tier on every row' {
            foreach ($set in $script:Attributes, $script:Roles, $script:Groups, $script:Apps, $script:Mappings, $script:Users,
                $script:Policies, $script:ApiAuthorizations, $script:AppRules, $script:Hooks, $script:SelfRegistrations) {
                @($set).Count | Should-BeGreaterThan 0
                @($set | Where-Object { -not $_.Purpose -or $_.Tier -notin 'Core', 'Bulk' }) | Should-BeCollection -Count 0
            }
        }

        It 'has unique keys in every keyed file' {
            foreach ($pair in @(
                    @{ Rows = $script:Users; Key = 'Key' }, @{ Rows = $script:Roles; Key = 'Key' }, @{ Rows = $script:Groups; Key = 'Key' }
                    @{ Rows = $script:Apps; Key = 'Key' }, @{ Rows = $script:Mappings; Key = 'Key' }, @{ Rows = $script:Attributes; Key = 'Shortname' }
                    @{ Rows = $script:Policies; Key = 'Key' }, @{ Rows = $script:ApiAuthorizations; Key = 'Key' }, @{ Rows = $script:AppRules; Key = 'Key' }
                    @{ Rows = $script:Hooks; Key = 'Key' }, @{ Rows = $script:SelfRegistrations; Key = 'Key' }
                )) {
                $keys = @($pair.Rows.($pair.Key))
                @($keys | Sort-Object -Unique).Count | Should-Be $keys.Count
            }
        }

        It 'keeps every username key plain ASCII, whatever the name' {
            @($script:Users | Where-Object { $_.Key -notmatch '^[a-z0-9._-]+$' }) | Should-BeCollection -Count 0
        }
    }

    Context 'Ownership and isolation' {

        It 'declares the field that carries the seed tag, and gives every field the attribute prefix' {
            # A field has no description, so the shortname is the only thing about it teardown can
            # check. Letters, digits and underscores only: OneLogin refuses a dash.
            @($script:Attributes | Where-Object Shortname -ceq 'zztest_seed_tag') | Should-BeCollection -Count 1
            @($script:Attributes | Where-Object { $_.Shortname -cnotmatch '^zztest_[a-z0-9_]+$' }) | Should-BeCollection -Count 0
        }

        It 'gives every role and every group a Core member who can hold it, so each can be proved at teardown' {
            $core = @($script:Users | Where-Object Tier -eq 'Core')
            foreach ($role in $script:Roles) {
                @($core | Where-Object { (& $script:Split $_.Roles) -contains $role.Key -and (& $script:CanHoldRole $_) }).Count |
                    Should-BeGreaterThan 0 -Because "role $($role.Key) would otherwise be empty, and an empty role cannot be proved"
            }
            foreach ($group in $script:Groups) {
                @($core | Where-Object Group -eq $group.Key).Count | Should-BeGreaterThan 0 -Because "group $($group.Key) would otherwise be empty"
            }
        }

        It 'attaches every policy to seeded groups that have a Core member, so each policy can be proved' {
            $core = @($script:Users | Where-Object Tier -eq 'Core' | ForEach-Object Group | Where-Object { $_ })
            foreach ($policy in $script:Policies) {
                $groups = @(& $script:Split $policy.Groups)
                $groups.Count | Should-BeGreaterThan 0
                @($groups | Where-Object { @($script:Groups.Key) -notcontains $_ }) | Should-BeCollection -Count 0
                @($groups | Where-Object { $core -contains $_ }).Count | Should-BeGreaterThan 0
            }
            # One policy per group: a group holds one policy, and two claiming it would fight.
            $claimed = @($script:Policies | ForEach-Object { & $script:Split $_.Groups })
            @($claimed | Sort-Object -Unique).Count | Should-Be $claimed.Count
        }

        It 'has no column that could give a role an administrator, a policy default status, a hook an enabled flag or a sign-up profile a default role' {
            # Each of those is a way out of the seed into the account, and none has a column.
            $script:Roles[0].PSObject.Properties.Name | Should-NotContainCollection 'Admins'
            $script:Policies[0].PSObject.Properties.Name | Should-NotContainCollection 'Default'
            $script:Hooks[0].PSObject.Properties.Name | Should-NotContainCollection 'Enabled'
            $script:SelfRegistrations[0].PSObject.Properties.Name | Should-NotContainCollection 'Enabled'
            $script:SelfRegistrations[0].PSObject.Properties.Name | Should-NotContainCollection 'DefaultRole'
            $script:SelfRegistrations[0].PSObject.Properties.Name | Should-NotContainCollection 'DefaultGroup'
        }

        It 'gives every person a distinct AD user name within twenty characters and a distinct employee id' {
            # Both are written behind the seed prefix, which keeps them from naming a real AD account
            # or employee; they also have to stay distinct once cut to AD's twenty characters.
            $sam = @($script:Users | ForEach-Object { $s = 'zz-test-' + $_.Key; if ($s.Length -gt 20) { $s.Substring(0, 20) } else { $s } })
            @($sam | Sort-Object -Unique).Count | Should-Be $sam.Count
            @($script:Users | Where-Object { -not $_.EmployeeId }) | Should-BeCollection -Count 0
            @($script:Users.EmployeeId | Sort-Object -Unique).Count | Should-Be $script:Users.Count
        }

        It 'uses only phone numbers from the range reserved for fiction, so none can reach a real phone' {
            @($script:Users | Where-Object { -not $_.Phone -or $_.Phone -notmatch '\) 555-01\d\d$' }) | Should-BeCollection -Count 0
        }
    }

    Context 'What OneLogin keeps' {

        It 'uses only statuses and states that stay put' {
            @($script:Users | Where-Object { $_.Status -notin 'Active', 'Suspended', 'Locked', 'PasswordExpired', 'AwaitingPasswordReset', 'PasswordPending' }) |
                Should-BeCollection -Count 0
            @($script:Users | Where-Object { $_.State -notin 'Approved', 'Rejected', 'Unlicensed' }) | Should-BeCollection -Count 0
        }

        It 'locks only licensed people, because OneLogin refuses to lock anybody else' {
            @($script:Users | Where-Object Status -eq 'Locked').Count | Should-BeGreaterThan 0
            @($script:Users | Where-Object { $_.Status -eq 'Locked' -and $_.State -ne 'Approved' }) | Should-BeCollection -Count 0
        }

        It 'approves at most ten people, so a trial''s twelve licences cover them with the owner and one to spare' {
            @($script:Users | Where-Object State -eq 'Approved').Count | Should-BeLessThanOrEqual 10
        }

        It 'gives roles only to people OneLogin lets hold one' {
            @($script:Users | Where-Object { $_.Roles -and -not (& $script:CanHoldRole $_) } | ForEach-Object Key) | Should-BeCollection -Count 0
        }

        It 'puts a rejected person in no group' {
            @($script:Users | Where-Object { $_.State -eq 'Rejected' -and $_.Group }) | Should-BeCollection -Count 0
        }

        It 'makes every Bulk person unlicensed and roleless, so a seed spends no licence' {
            @($script:Users | Where-Object { $_.Tier -eq 'Bulk' -and ($_.State -ne 'Unlicensed' -or $_.Roles) }) | Should-BeCollection -Count 0
            @($script:Users | Where-Object Tier -eq 'Bulk').Count | Should-BeGreaterThan 250
        }

        It 'fits a trial: four roles beside Default, and five apps' {
            $script:Roles.Count | Should-BeLessThanOrEqual 4
            $script:Apps.Count | Should-BeLessThanOrEqual 5
        }

        It 'asks for an MFA factor only on people who hold a licence, and only one OneLogin enrols pre-verified' {
            @($script:Users | Where-Object { $_.Mfa -and $_.State -ne 'Approved' }) | Should-BeCollection -Count 0
            @($script:Users | Where-Object { $_.Mfa -and $_.Mfa -notin 'Email', 'SMS', 'Voice' }) | Should-BeCollection -Count 0
        }

        It 'asks only for locales OneLogin accepts' {
            # Verified live: tr-TR, ja, de and en are accepted; tr_TR is refused.
            @($script:Users | Where-Object { $_.Locale -and $_.Locale -notin 'tr-TR', 'ja', 'de', 'en' }) | Should-BeCollection -Count 0
        }

        It 'names only connectors and token methods the provider knows' {
            @($script:Apps | Where-Object { $_.Connector -notin 'OIDC', 'SAML' }) | Should-BeCollection -Count 0
            @($script:Apps | Where-Object { $_.Connector -eq 'OIDC' -and ($_.TokenAuth -notin 'Basic', 'Post', 'None' -or $_.AppType -notin 'Web', 'Native' -or -not $_.RedirectUri) }) |
                Should-BeCollection -Count 0
            @($script:Apps | Where-Object { $_.Connector -eq 'SAML' -and (-not $_.Audience -or -not $_.ConsumerUrl) }) | Should-BeCollection -Count 0
        }

        It 'writes every URL against the connection''s domain or a custom scheme, never a real host' {
            $urls = @($script:Apps | ForEach-Object { $_.LoginUrl; $_.RedirectUri; $_.Audience; $_.ConsumerUrl } | Where-Object { $_ -like 'http*' })
            $urls.Count | Should-BeGreaterThan 0
            @($urls | Where-Object { $_ -notlike 'https://*.{domain}/*' }) | Should-BeCollection -Count 0
            # An API's identifier is a path the provider puts under the lab domain; a full URL here
            # would name some other host.
            @($script:ApiAuthorizations | Where-Object { $_.Path -match '[:/.]' }) | Should-BeCollection -Count 0
        }
    }

    Context 'References resolve' {

        It 'names only roles and groups that exist' {
            $roleKeys = @($script:Roles.Key); $groupKeys = @($script:Groups.Key)
            $bad = foreach ($user in $script:Users) {
                foreach ($role in (& $script:Split $user.Roles)) { if ($roleKeys -notcontains $role) { "$($user.Key)->$role" } }
                if ($user.Group -and $groupKeys -notcontains $user.Group) { "$($user.Key)->$($user.Group)" }
            }
            foreach ($app in $script:Apps) { foreach ($role in (& $script:Split $app.Roles)) { if ($roleKeys -notcontains $role) { "$($app.Key)->$role" } } }
            foreach ($row in @($script:Mappings) + @($script:AppRules) + @($script:Hooks)) { if ($roleKeys -notcontains $row.Role) { "$($row.Key)->$($row.Role)" } }
            @($bad) | Should-BeCollection -Count 0
        }

        It 'puts app rules only on OIDC apps, with an operator OneLogin knows' {
            # set_groups is the OIDC connector's groups claim; a SAML app has no such action.
            $oidc = @($script:Apps | Where-Object Connector -eq 'OIDC' | ForEach-Object Key)
            @($script:AppRules | Where-Object { $oidc -notcontains $_.App }) | Should-BeCollection -Count 0
            @($script:AppRules | Where-Object { $_.Operator -notin 'ri', 'rin' -or -not $_.Expression }) | Should-BeCollection -Count 0
        }

        It 'grants API clients only scopes the server declares, to apps that exist' {
            $appKeys = @($script:Apps.Key)
            $bad = foreach ($server in $script:ApiAuthorizations) {
                $declared = @(([string]$server.Scopes -split '\|') | Where-Object { $_ } | ForEach-Object { ($_ -split '=', 2)[0] })
                foreach ($client in @(([string]$server.Clients -split '\|') | Where-Object { $_ })) {
                    $appKey, $scopes = $client -split '=', 2
                    if ($appKeys -notcontains $appKey) { "$($server.Key)->$appKey" }
                    foreach ($scope in @(([string]$scopes -split ' ') | Where-Object { $_ })) { if ($declared -notcontains $scope) { '{0}:{1}:{2}' -f $server.Key, $appKey, $scope } }
                }
            }
            @($bad) | Should-BeCollection -Count 0
        }

        It 'names only seeded managers, each listed before the people who report to them' {
            $position = @{}
            for ($i = 0; $i -lt $script:Users.Count; $i++) { $position[$script:Users[$i].Key] = $i }
            @($script:Users | Where-Object { $_.Manager -and -not $position.ContainsKey($_.Manager) }) | Should-BeCollection -Count 0
            @($script:Users | Where-Object { $_.Manager -and $position[$_.Manager] -gt $position[$_.Key] } | ForEach-Object Key) | Should-BeCollection -Count 0
        }

        It 'gives Core people Core managers only, so a Core seed is complete in itself' {
            $core = @{}; foreach ($user in ($script:Users | Where-Object Tier -eq 'Core')) { $core[$user.Key] = $true }
            @($script:Users | Where-Object { $_.Tier -eq 'Core' -and $_.Manager -and -not $core.ContainsKey($_.Manager) }) | Should-BeCollection -Count 0
        }

        It 'writes every mapping condition as source|operator|value, and none that names the seed tag itself' {
            # The provider adds the seed-tag condition to every mapping; the data never carries it,
            # so there is no way to write a mapping whose gate differs from the one the code writes.
            foreach ($mapping in $script:Mappings) {
                foreach ($condition in (& $script:Split $mapping.Conditions)) {
                    @($condition -split '\|').Count | Should-Be 3
                    $condition | Should-NotMatchString 'zztest_seed_tag'
                }
            }
        }
    }

    Context 'The awkward shapes the provider exists to seed' {

        It 'has a suspended manager with reports, a locked person holding a role, and one enabled mapping and one disabled' {
            $suspended = @($script:Users | Where-Object Status -eq 'Suspended' | Where-Object Tier -eq 'Core').Key
            @($script:Users | Where-Object { $suspended -contains $_.Manager }).Count | Should-BeGreaterThan 0
            @($script:Users | Where-Object { $_.Status -eq 'Locked' -and $_.Roles }).Count | Should-BeGreaterThan 0
            @($script:Mappings | Where-Object Enabled -eq 'TRUE').Count | Should-Be 1
            @($script:Mappings | Where-Object Enabled -eq 'FALSE').Count | Should-Be 1
        }

        It 'has a public client, a native client, a SAML app, an app granted to no role, and a dormant app rule' {
            @($script:Apps | Where-Object TokenAuth -eq 'None').Count | Should-BeGreaterThan 0
            @($script:Apps | Where-Object AppType -eq 'Native').Count | Should-BeGreaterThan 0
            @($script:Apps | Where-Object Connector -eq 'SAML').Count | Should-BeGreaterThan 0
            @($script:Apps | Where-Object { -not $_.Roles }).Count | Should-BeGreaterThan 0
            @($script:AppRules | Where-Object Enabled -eq 'FALSE').Count | Should-BeGreaterThan 0
        }

        It 'has a group with no policy of its own, and an API scope granted to no client' {
            $governed = @($script:Policies | ForEach-Object { & $script:Split $_.Groups })
            @($script:Groups | Where-Object { $governed -notcontains $_.Key }).Count | Should-BeGreaterThan 0
            $unused = foreach ($server in $script:ApiAuthorizations) {
                $granted = @(([string]$server.Clients -split '\|') | Where-Object { $_ } | ForEach-Object { (($_ -split '=', 2)[1] -split ' ') })
                @(([string]$server.Scopes -split '\|') | Where-Object { $_ } | ForEach-Object { ($_ -split '=', 2)[0] } | Where-Object { $granted -notcontains $_ })
            }
            @($unused).Count | Should-BeGreaterThan 0
        }

        It 'covers writing systems beyond Latin, in the names and in the directory display names' {
            foreach ($block in '\p{IsCJKUnifiedIdeographs}', '\p{IsCyrillic}', '\p{IsGreekandCoptic}', '\p{IsArabic}', '\p{IsDevanagari}') {
                @($script:Users | Where-Object { "$($_.GivenName) $($_.Surname)" -match $block }).Count | Should-BeGreaterThan 0
            }
            # The ideographic space survives into the display name, which becomes a DN's common name.
            ($script:Users | Where-Object Key -eq 'jjiang').DisplayName.IndexOf([char]0x3000) | Should-BeGreaterThan 0
        }

        It 'keeps the decomposed name decomposed' {
            # Checked on the codepoint, not with -eq, which calls the two forms equal.
            ($script:Users | Where-Object Key -eq 'jmarchetti').GivenName.IndexOf([char]0x0301) | Should-BeGreaterThan 0
            ($script:Users | Where-Object Key -eq 'jnino').GivenName.IndexOf([char]0x0301) | Should-Be (-1)
        }
    }
}
