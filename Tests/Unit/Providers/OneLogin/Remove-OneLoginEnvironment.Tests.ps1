#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown safety for the OneLogin provider.

    The two failures every provider's teardown is pinned against, because neither produces an
    error: -Force defeating -WhatIf, and a refused confirmation that does not stop anything. And the
    ones that are OneLogin's own: every proof taken before the first deletion, because a role is
    proved by the users and apps it holds, a policy by its groups, a mapping and a hook by the roles
    they name; the deletions in the only order that keeps the later proofs standing; and -Keep
    keeping everything the kept type is proved by, so nothing is left that no later teardown could
    claim.

    Every call is mocked. This suite must never reach an account.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Remove-OneLoginEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com'; Prefix = 'ZZ-TEST-'; EmailDomain = 'onelogin-lab.example.com' } }
            Mock Write-TestMessage { }
            Mock Write-Host { }
            # Never the real credential folder; saved app secrets have a suite of their own.
            Mock Get-OneLoginAppSecretRecord { }

            $script:Events = [System.Collections.Generic.List[string]]::new()
            Mock Get-OneLoginSeededObject -ParameterFilter { $Unproven } {
                if ($Type -eq 'Roles') { [PSCustomObject]@{ Type = 'Roles'; Id = '99'; Name = 'ZZ-TEST-Someone else'; Reason = 'It holds 1 user(s) that are not seeded' } }
            }
            Mock Get-OneLoginSeededObject -ParameterFilter { -not $Unproven } {
                $script:Events.Add("prove $Type")
                switch ($Type) {
                    'Users' { [PSCustomObject]@{ id = 10; username = 'zz-test-jnino' } }
                    'Apps' { [PSCustomObject]@{ id = 50; name = 'ZZ-TEST-Expenses Web' } }
                    'Roles' { [PSCustomObject]@{ id = 1; name = 'ZZ-TEST-All Staff' } }
                    'Groups' { [PSCustomObject]@{ id = 2; name = 'ZZ-TEST-Seattle HQ' } }
                    'Policies' { [PSCustomObject]@{ id = 5; name = 'ZZ-TEST-Strict Office' } }
                    'Mappings' { [PSCustomObject]@{ id = 3; name = 'ZZ-TEST-Finance' } }
                    'AppRules' { [PSCustomObject]@{ id = 6; name = 'ZZ-TEST-Directory groups'; AppId = '50' } }
                    'Hooks' { [PSCustomObject]@{ id = 'h1'; name = 'pre-authentication hook h1' } }
                    'ApiAuthorizations' { [PSCustomObject]@{ id = 7; name = 'ZZ-TEST-Orders API' } }
                    'SelfRegistration' { [PSCustomObject]@{ id = 8; name = 'ZZ-TEST-Partner Sign-up' } }
                    'Attributes' { [PSCustomObject]@{ id = 4; shortname = 'zztest_seed_tag' } }
                }
            }
            Mock Invoke-OneLoginRequest { throw "Escaped the mocks: $Method $Path" }
            Mock Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'DELETE' } { $script:Events.Add("delete $Path") }
        }
    }

    Context 'WhatIf wins over Force' {

        It 'deletes nothing with -Force -WhatIf, and reports nothing removed' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -WhatIf -PassThru
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'DELETE' }
                $result.TotalRemoved | Should-Be 0
            }
        }

        It 'previews without -Force rather than treating the preview as a refusal' {
            InModuleScope TestEnvironment {
                Mock Confirm-TestTeardown { throw 'A preview must not ask.' }
                $result = Remove-OneLoginEnvironment -WhatIf -PassThru
                $result.Cancelled | Should-BeFalse
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'DELETE' }
            }
        }
    }

    Context 'A refusal actually stops the run' {

        It 'deletes and proves nothing when the question is refused or cannot be asked' {
            InModuleScope TestEnvironment {
                Mock Confirm-TestTeardown { $false }
                $result = Remove-OneLoginEnvironment -PassThru
                $result.Cancelled | Should-BeTrue
                $result.TotalRemoved | Should-Be 0
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Method -eq 'DELETE' }
                Should-NotInvoke Get-OneLoginSeededObject
            }
        }
    }

    Context 'Force removes, proving first' {

        It 'proves every type before deleting anything, then deletes in the order the proofs need' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -PassThru
                # Ten, not eleven: the app rule goes with its app rather than on its own.
                $result.TotalRemoved | Should-Be 10

                $firstDelete = [array]::FindIndex($script:Events.ToArray(), [Predicate[string]] { param($e) $e.StartsWith('delete') })
                $lastProve = [array]::FindLastIndex($script:Events.ToArray(), [Predicate[string]] { param($e) $e.StartsWith('prove') })
                $lastProve | Should-BeLessThan $firstDelete

                @($script:Events | Where-Object { $_.StartsWith('delete') }) | Should-BeCollection @(
                    'delete self_registration_profiles/8', 'delete hooks/h1', 'delete mappings/3', 'delete api_authorizations/7',
                    'delete roles/1', 'delete groups/2', 'delete policies/5', 'delete apps/50', 'delete users/10', 'delete users/custom_attributes/4')
            }
        }

        It 'proves roles against the users and apps it found, and policies, mappings, rules and hooks against those' {
            InModuleScope TestEnvironment {
                $null = Remove-OneLoginEnvironment -Force
                Should-Invoke Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Roles' -and -not $Unproven -and @($OwnedUserId) -contains '10' -and @($OwnedAppId) -contains '50' }
                foreach ($type in 'Mappings', 'Hooks', 'AppRules') {
                    Should-Invoke Get-OneLoginSeededObject -ParameterFilter { $Type -eq $type -and -not $Unproven -and @($OwnedRoleId) -contains '1' }
                }
                Should-Invoke Get-OneLoginSeededObject -ParameterFilter { $Type -eq 'Policies' -and -not $Unproven -and @($OwnedGroupId) -contains '2' }
            }
        }

        It 'names what it left alone, with the reason' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -PassThru
                @($result.LeftAlone).Count | Should-Be 1
                $result.LeftAlone[0].Name | Should-Be 'ZZ-TEST-Someone else'
                Should-NotInvoke Invoke-OneLoginRequest -ParameterFilter { $Path -eq 'roles/99' }
            }
        }
    }

    Context 'Keep keeps what the kept type is proved by' {

        It 'keeps the fields with the users, because the tag in one is their only proof' {
            InModuleScope TestEnvironment {
                $result = Remove-OneLoginEnvironment -Force -Keep Users -PassThru
                @($script:Events | Where-Object { $_ -like 'delete users*' }) | Should-BeCollection -Count 0
                @($result.Errors | Where-Object { $_ -like 'Also kept*Attributes*' }) | Should-BeCollection -Count 1
                @($script:Events | Where-Object { $_ -like 'delete roles/*' }) | Should-BeCollection -Count 1
            }
        }

        It 'keeps the people, apps and fields with the roles, and the groups, people and fields with the policies' {
            InModuleScope TestEnvironment {
                $null = Remove-OneLoginEnvironment -Force -Keep Roles
                @($script:Events | Where-Object { $_ -like 'delete users*' -or $_ -eq 'delete apps/50' -or $_ -like 'delete roles/*' }) | Should-BeCollection -Count 0
                @($script:Events | Where-Object { $_ -like 'delete groups/*' }) | Should-BeCollection -Count 1
                # The app stays, so its rule, which is not kept, is deleted on its own.
                @($script:Events | Where-Object { $_ -eq 'delete apps/50/rules/6' }) | Should-BeCollection -Count 1

                $script:Events.Clear()
                $null = Remove-OneLoginEnvironment -Force -Keep Policies
                @($script:Events | Where-Object { $_ -like 'delete policies/*' -or $_ -like 'delete groups/*' -or $_ -like 'delete users*' }) | Should-BeCollection -Count 0
                @($script:Events | Where-Object { $_ -like 'delete roles/*' }) | Should-BeCollection -Count 1
            }
        }

        It 'keeps the roles with the mappings and the hook, and deletes an app rule on its own when its app stays' {
            InModuleScope TestEnvironment {
                $null = Remove-OneLoginEnvironment -Force -Keep Hooks
                @($script:Events | Where-Object { $_ -like 'delete roles/*' -or $_ -like 'delete hooks/*' }) | Should-BeCollection -Count 0

                $script:Events.Clear()
                $null = Remove-OneLoginEnvironment -Force -Keep Apps
                @($script:Events | Where-Object { $_ -eq 'delete apps/50/rules/6' }) | Should-BeCollection -Count 1
                @($script:Events | Where-Object { $_ -eq 'delete apps/50' }) | Should-BeCollection -Count 0
            }
        }
    }
}
