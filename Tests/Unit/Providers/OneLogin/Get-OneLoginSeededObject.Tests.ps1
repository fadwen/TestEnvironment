#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Ownership discovery for the OneLogin provider - the only thing teardown deletes from, and what
    the report and the verifier read.

    A OneLogin account is as likely to be somebody's production directory as a lab, so the rule
    that nothing is deleted for merely matching a name carries more weight here than anywhere. A
    role, a group, a policy, a mapping and a hook have nothing but a name - a hook not even that - so
    each is proved by what it holds or names. These pin every refusal: a prefixed role holding one
    real person, an empty prefixed role, a role with an administrator, a group with somebody else's
    policy, a policy used by a real group, the account's default policy, a mapping without the
    seed-tag condition, a mapping, rule or hook naming a real role, a hook without the marker, an app
    or API server with the prefix and no tag, a sign-up profile with the prefix and no tag, a user
    with the prefix and no tag, a custom field the data does not declare. And one acceptance that
    keeps teardown able to finish what it started: a role that no longer exists grants nothing, so
    naming one does not make a mapping, rule or hook somebody else's.

    Every call is mocked. This suite must never reach an account.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-OneLoginSeededObject' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' }
            # The backstop. A call no test mocked would otherwise run the real function and reach
            # OneLogin; it fails loudly instead, naming the path.
            Mock Invoke-OneLoginRequest { throw "Escaped the mocks: $Method $Path" }
            # Every role in the account: two seeded, the Default role, and one a person made.
            Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'roles' } {
                foreach ($id in 7, 8, 1000001, 555) { [PSCustomObject]@{ id = $id; name = "role $id"; users = @(); apps = @(); admins = @() } }
            }
        }
    }

    Context 'Users need the tag and the prefix' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users/custom_attributes' } {
                    , @([PSCustomObject]@{ id = 1; shortname = 'zztest_seed_tag' })
                }
            }
        }

        It 'claims a user with both, and asks for the fields that carry the tag' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users' } {
                    [PSCustomObject]@{ id = 10; username = 'zz-test-jnino'; custom_attributes = [PSCustomObject]@{ zztest_seed_tag = 'ZZ-TEST-seed' } }
                }
                @(Get-OneLoginSeededObject -Type Users -Connection $script:Connection).id | Should-BeCollection @(10)
                # The listing leaves custom_attributes out unless it is named; found live, when the
                # first seed proved nobody.
                Should-Invoke Invoke-OneLoginRequest -ParameterFilter {
                    $Path -eq 'users' -and $Query['custom_attributes.zztest_seed_tag'] -eq 'ZZ-TEST-seed' -and $Query.fields -like '*custom_attributes*'
                }
            }
        }

        It 'refuses a tagged user without the prefix, a prefixed user without the tag, and a tag that only resembles it' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users' } {
                    [PSCustomObject]@{ id = 1; username = 'jane.real'; custom_attributes = [PSCustomObject]@{ zztest_seed_tag = 'ZZ-TEST-seed' } }
                    [PSCustomObject]@{ id = 2; username = 'zz-test-lookalike'; custom_attributes = [PSCustomObject]@{ zztest_seed_tag = $null } }
                    [PSCustomObject]@{ id = 3; username = 'zz-test-loose'; custom_attributes = [PSCustomObject]@{ zztest_seed_tag = 'zz-test-SEED' } }
                    [PSCustomObject]@{ id = 4; username = 'zz-test-nofields' }
                }
                @(Get-OneLoginSeededObject -Type Users -Connection $script:Connection) | Should-BeCollection -Count 0
            }
        }

        It 'asks for no users at all when the tag field does not exist' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users/custom_attributes' } { , @() }
                @(Get-OneLoginSeededObject -Type Users -Connection $script:Connection) | Should-BeCollection -Count 0
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users' }
            }
        }
    }

    Context 'Apps, API servers and sign-up profiles need the tag and the prefix' {

        It 'claims only an app with both, and names the other prefixed one as unproven' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'apps' } {
                    [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Expenses Web'; description = 'Seeded. [ZZ-TEST-seed]' }
                    [PSCustomObject]@{ id = 2; name = 'Salesforce'; description = 'Copied from a wiki: ZZ-TEST-seed' }
                    [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Made by a person'; description = 'Ours, honestly' }
                }
                @(Get-OneLoginSeededObject -Type Apps -Connection $script:Connection).id | Should-BeCollection @(1)
                $unproven = @(Get-OneLoginSeededObject -Type Apps -Unproven -Connection $script:Connection)
                $unproven.Id | Should-BeCollection @('3')
                $unproven[0].Reason | Should-MatchString 'seed tag'
            }
        }

        It 'proves an API authorization server the same way' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'api_authorizations' } {
                    [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Orders API'; description = 'Seeded API. [ZZ-TEST-seed]' }
                    [PSCustomObject]@{ id = 2; name = 'Payments API'; description = 'ZZ-TEST-seed' }
                    [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Real API'; description = 'The real one' }
                }
                @(Get-OneLoginSeededObject -Type ApiAuthorizations -Connection $script:Connection).id | Should-BeCollection @(1)
                @(Get-OneLoginSeededObject -Type ApiAuthorizations -Unproven -Connection $script:Connection).Id | Should-BeCollection @('3')
            }
        }

        It 'proves a sign-up profile by the tag in its help text, read from the profile itself' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'self_registration_profiles' } {
                    [PSCustomObject]@{ self_registration_profiles = @(
                            [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Partner Sign-up' }
                            [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Real Sign-up' }
                            [PSCustomObject]@{ id = 3; name = 'Customer Sign-up' }
                        ) }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'self_registration_profiles/1' } { [PSCustomObject]@{ self_registration_profile = [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Partner Sign-up'; helptext = 'Seeded. [ZZ-TEST-seed]' } } }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'self_registration_profiles/2' } { [PSCustomObject]@{ self_registration_profile = [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Real Sign-up'; helptext = 'Welcome' } } }
                @(Get-OneLoginSeededObject -Type SelfRegistration -Connection $script:Connection).id | Should-BeCollection @(1)
                @(Get-OneLoginSeededObject -Type SelfRegistration -Unproven -Connection $script:Connection).Id | Should-BeCollection @('2')
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'self_registration_profiles/3' }
            }
        }
    }

    Context 'Roles are proved by what they hold' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'roles' } {
                    [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-All Staff'; users = @(10, 11); apps = @(50); admins = @() }
                    [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Finance'; users = @(10, 999); apps = @(); admins = @() }
                    [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Empty'; users = @(); apps = @(); admins = @() }
                    [PSCustomObject]@{ id = 4; name = 'ZZ-TEST-Admins'; users = @(10); apps = @(); admins = @(999) }
                    [PSCustomObject]@{ id = 5; name = 'ZZ-TEST-Foreign App'; users = @(10); apps = @(77); admins = @() }
                    [PSCustomObject]@{ id = 6; name = 'Default'; users = @(10); apps = @(); admins = @() }
                }
            }
        }

        It 'claims a prefixed role holding only seeded users and apps, and nothing else' {
            InModuleScope TestEnvironment {
                @(Get-OneLoginSeededObject -Type Roles -OwnedUserId '10', '11' -OwnedAppId '50' -Connection $script:Connection).id |
                    Should-BeCollection @(1)
            }
        }

        It 'refuses one real person, an empty role, an administrator and a foreign app, and says which' {
            InModuleScope TestEnvironment {
                $unproven = @(Get-OneLoginSeededObject -Type Roles -Unproven -OwnedUserId '10', '11' -OwnedAppId '50' -Connection $script:Connection)
                $byId = @{}; foreach ($item in $unproven) { $byId[$item.Id] = $item.Reason }
                ($byId.Keys | Sort-Object) | Should-BeCollection @('2', '3', '4', '5')
                $byId['2'] | Should-MatchString 'not seeded'
                $byId['3'] | Should-MatchString 'no users and no apps'
                $byId['4'] | Should-MatchString 'administrators'
                $byId['5'] | Should-MatchString 'app'
            }
        }

        It 'lets the seed reuse an empty role under -AllowEmpty, and nothing more' {
            InModuleScope TestEnvironment {
                @(Get-OneLoginSeededObject -Type Roles -AllowEmpty -OwnedUserId '10', '11' -OwnedAppId '50' -Connection $script:Connection).id |
                    Sort-Object | Should-BeCollection @(1, 3)
            }
        }
    }

    Context 'Groups are proved by their members, and by a policy that is the seed''s' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'policies' } {
                    , @(
                        [PSCustomObject]@{ id = 900; name = 'Default policy'; kind = 'user'; is_default = $true }
                        [PSCustomObject]@{ id = 901; name = 'ZZ-TEST-Strict Office'; kind = 'user'; is_default = $false }
                        [PSCustomObject]@{ id = 902; name = 'Executives'; kind = 'user'; is_default = $false }
                    )
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'groups' } {
                    foreach ($id in 1..6) { [PSCustomObject]@{ id = $id; name = "ZZ-TEST-Group $id"; policy_id = $null } }
                    [PSCustomObject]@{ id = 7; name = 'Engineering'; policy_id = $null }
                }
                # The detail, which is where the administrators are.
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -like 'groups/*' } {
                    $id = [int]($Path -replace '^groups/', '')
                    $policy = switch ($id) { 2 { 901 } 3 { 902 } 4 { 900 } default { $null } }
                    $admins = if ($id -eq 5) { @(999) } else { @() }
                    [PSCustomObject]@{ id = $id; name = "ZZ-TEST-Group $id"; policy_id = $policy; admins = $admins }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users' -and $Query.group_id -in '1', '2', '3', '4', '5' } { [PSCustomObject]@{ id = 10 } }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users' -and $Query.group_id -eq '6' } { [PSCustomObject]@{ id = 10 }; [PSCustomObject]@{ id = 999 } }
            }
        }

        It 'claims a group of seeded members with no policy or the seed''s own, and never asks about an unprefixed one' {
            InModuleScope TestEnvironment {
                $claimed = @(Get-OneLoginSeededObject -Type Groups -OwnedUserId '10' -Connection $script:Connection)
                ($claimed.id | Sort-Object) | Should-BeCollection @(1, 2)
                $claimed[0].MemberIds | Should-BeCollection @('10')
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'groups/7' }
            }
        }

        It 'refuses somebody else''s policy, the default policy, an administrator and a real person' {
            InModuleScope TestEnvironment {
                $unproven = @(Get-OneLoginSeededObject -Type Groups -Unproven -OwnedUserId '10' -Connection $script:Connection)
                ($unproven.Id | Sort-Object) | Should-BeCollection @('3', '4', '5', '6')
                ($unproven | Where-Object Id -eq '3').Reason | Should-MatchString 'policy'
                ($unproven | Where-Object Id -eq '5').Reason | Should-MatchString 'administrators'
            }
        }
    }

    Context 'Policies are proved by the groups that use them' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'policies' } {
                    , @(
                        [PSCustomObject]@{ id = 900; name = 'ZZ-TEST-Default'; kind = 'user'; is_default = $true }
                        [PSCustomObject]@{ id = 901; name = 'ZZ-TEST-Strict Office'; kind = 'user'; is_default = $false }
                        [PSCustomObject]@{ id = 902; name = 'ZZ-TEST-Shared'; kind = 'user'; is_default = $false }
                        [PSCustomObject]@{ id = 903; name = 'ZZ-TEST-Unused'; kind = 'user'; is_default = $false }
                        [PSCustomObject]@{ id = 904; name = 'Executives'; kind = 'user'; is_default = $false }
                    )
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'groups' } {
                    [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Seattle HQ'; policy_id = 901 }
                    [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-London'; policy_id = 902 }
                    [PSCustomObject]@{ id = 3; name = 'Finance'; policy_id = 902 }
                    [PSCustomObject]@{ id = 4; name = 'ZZ-TEST-Remote'; policy_id = 900 }
                }
            }
        }

        It 'claims a prefixed policy used only by seeded groups' {
            InModuleScope TestEnvironment {
                $claimed = @(Get-OneLoginSeededObject -Type Policies -OwnedUserId '10' -OwnedGroupId '1', '2', '4' -Connection $script:Connection)
                $claimed.id | Should-BeCollection @(901)
                $claimed[0].GroupIds | Should-BeCollection @('1')
            }
        }

        It 'refuses the default, a policy a real group uses, and an unused one - and never names an unprefixed one' {
            InModuleScope TestEnvironment {
                $unproven = @(Get-OneLoginSeededObject -Type Policies -Unproven -OwnedUserId '10' -OwnedGroupId '1', '2', '4' -Connection $script:Connection)
                ($unproven.Id | Sort-Object) | Should-BeCollection @('900', '902', '903')
                ($unproven | Where-Object Id -eq '900').Reason | Should-MatchString 'default'
                ($unproven | Where-Object Id -eq '902').Reason | Should-MatchString 'not seeded'
                ($unproven | Where-Object Id -eq '903').Reason | Should-MatchString 'No group uses it'
            }
        }
    }

    Context 'Mappings, app rules and hooks are proved by the roles they name' {

        BeforeEach {
            InModuleScope TestEnvironment {
                $script:Gate = [PSCustomObject]@{ source = 'custom_attribute_zztest_seed_tag'; operator = '='; value = 'ZZ-TEST-seed' }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'mappings' -and -not $Query } {
                    , @(
                        [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Finance dept'; match = 'all'; conditions = @($script:Gate, [PSCustomObject]@{ source = 'department'; operator = '='; value = 'Finance' }); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('7') }) }
                        [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Ungated'; match = 'all'; conditions = @([PSCustomObject]@{ source = 'department'; operator = '='; value = 'Finance' }); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('7') }) }
                        [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Any'; match = 'any'; conditions = @($script:Gate); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('7') }) }
                    )
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'mappings' -and $Query.enabled -eq 'false' } {
                    # One disabled mapping, which the listing hands back as the object itself: found
                    # live, when joining it to the enabled ones failed and hid both from teardown.
                    [PSCustomObject]@{ id = 4; name = 'ZZ-TEST-Disabled'; match = 'all'; conditions = @($script:Gate); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('8') }) }
                }
            }
        }

        It 'claims enabled and disabled mappings that are gated and add only seeded roles, even when a listing holds one' {
            InModuleScope TestEnvironment {
                @(Get-OneLoginSeededObject -Type Mappings -OwnedRoleId '7', '8' -Connection $script:Connection).id | Sort-Object |
                    Should-BeCollection @(1, 4)
            }
        }

        It 'refuses the ungated and the any-match, and a mapping that adds a real role' {
            InModuleScope TestEnvironment {
                $unproven = @(Get-OneLoginSeededObject -Type Mappings -Unproven -OwnedRoleId '7' -Connection $script:Connection)
                ($unproven.Id | Sort-Object) | Should-BeCollection @('2', '3', '4')
                ($unproven | Where-Object Id -eq '2').Reason | Should-MatchString 'seed tag'
                ($unproven | Where-Object Id -eq '4').Reason | Should-MatchString 'not seeded'
            }
        }

        It 'accepts a role that no longer exists, so a teardown that stopped halfway can finish' {
            # Found live: a mapping whose role an earlier teardown had deleted could never be claimed
            # again. A deleted role grants nothing; only an existing role that is somebody else's
            # makes the mapping theirs.
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'mappings' -and -not $Query } { , @() }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'mappings' -and $Query.enabled -eq 'false' } {
                    , @(
                        [PSCustomObject]@{ id = 5; name = 'ZZ-TEST-Orphan'; match = 'all'; conditions = @($script:Gate); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('4040') }) }
                        [PSCustomObject]@{ id = 6; name = 'ZZ-TEST-Real'; match = 'all'; conditions = @($script:Gate); actions = @([PSCustomObject]@{ action = 'add_role'; value = @('555') }) }
                    )
                }
                @(Get-OneLoginSeededObject -Type Mappings -OwnedRoleId '7' -Connection $script:Connection).id | Should-BeCollection @(5)
            }
        }

        It 'claims an app rule on a seeded app naming only seeded roles, and never looks at another app' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'apps/50/rules' -and -not $Query } {
                    [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-Directory groups'; conditions = @([PSCustomObject]@{ source = 'has_role'; operator = 'ri'; value = '7' }) }
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'apps/50/rules' -and $Query.enabled -eq 'false' } {
                    [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Real role'; conditions = @([PSCustomObject]@{ source = 'has_role'; operator = 'ri'; value = '555' }) }
                    [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Everyone'; conditions = @() }
                }
                $claimed = @(Get-OneLoginSeededObject -Type AppRules -OwnedAppId '50' -OwnedRoleId '7' -Connection $script:Connection)
                $claimed.id | Should-BeCollection @(1)
                $claimed[0].AppId | Should-Be '50'
                (@(Get-OneLoginSeededObject -Type AppRules -Unproven -OwnedAppId '50' -OwnedRoleId '7' -Connection $script:Connection).Id | Sort-Object) |
                    Should-BeCollection @('2', '3')
            }
        }

        It 'claims a hook by the marker in its code, read from the hook itself, and refuses one gated on nothing or on a real role' {
            InModuleScope TestEnvironment {
                $marked = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("// Seeded by TestEnvironment. Safe to delete. [ZZ-TEST-seed]`nexports.handler = async () => ({})"))
                $plain = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("exports.handler = async () => ({})"))
                # The listing leaves the code out, as OneLogin's does.
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'hooks' } { , @('a', 'b', 'c', 'd' | ForEach-Object { [PSCustomObject]@{ id = $_; type = 'pre-authentication' } }) }
                $script:Code = @{ a = $marked; b = $marked; c = $marked; d = $plain }
                $script:Conditions = @{
                    a = @([PSCustomObject]@{ source = 'roles'; operator = '~'; value = '7' })
                    b = @()
                    c = @([PSCustomObject]@{ source = 'roles'; operator = '~'; value = '555' })
                    d = @([PSCustomObject]@{ source = 'roles'; operator = '~'; value = '7' })
                }
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -like 'hooks/*' } {
                    $id = $Path -replace '^hooks/', ''
                    [PSCustomObject]@{ id = $id; type = 'pre-authentication'; disabled = $true; function = $script:Code[$id]; conditions = $script:Conditions[$id] }
                }
                @(Get-OneLoginSeededObject -Type Hooks -OwnedRoleId '7' -Connection $script:Connection).id | Should-BeCollection @('a')
                # A hook without the marker is not a candidate at all, and is never named.
                (@(Get-OneLoginSeededObject -Type Hooks -Unproven -OwnedRoleId '7' -Connection $script:Connection).Id | Sort-Object) | Should-BeCollection @('b', 'c')
            }
        }
    }

    Context 'Custom fields need declaring and the attribute prefix' {

        It 'claims only the fields the data declares' {
            InModuleScope TestEnvironment {
                Mock Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'users/custom_attributes' } {
                    , @(
                        [PSCustomObject]@{ id = 1; shortname = 'zztest_seed_tag' }
                        [PSCustomObject]@{ id = 2; shortname = 'zztest_badge_id' }
                        [PSCustomObject]@{ id = 3; shortname = 'cost_center' }
                        [PSCustomObject]@{ id = 4; shortname = 'zztest_made_by_hand' }
                        [PSCustomObject]@{ id = 5; shortname = 'ZZTEST_SEED_TAG' }
                    )
                }
                @(Get-OneLoginSeededObject -Type Attributes -Connection $script:Connection).id | Sort-Object | Should-BeCollection @(1, 2)
            }
        }
    }

    It 'refuses -Unproven for users and fields, which are not ours without their proof' {
        InModuleScope TestEnvironment {
            { Get-OneLoginSeededObject -Type Users -Unproven -Connection $script:Connection } | Should-Throw -ExceptionMessage '*-Unproven applies to*'
        }
    }
}
