#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown is the destructive half of the module, and the property that matters most is
    that -WhatIf wins over -Force: -Force defeating -WhatIf was the worst defect an earlier
    module shipped, and it is pinned here first. After that, the order - invitations and
    tokens first, bindings before the policies and entitlements they attach, entitlements
    before their applications, applications before their providers, scope mappings after the
    providers that carried them, roles before the groups that hold them, leaf groups before
    their parents, rules before their transports - and the promise that the service account
    is left alone unless asked for, and removed last when it is.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-AuthentikEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; CredentialPath = $null }
            }
            Mock Write-TestMessage { }
            Mock Write-Host { }

            Mock Get-AuthentikSeededObject {
                switch ($Type) {
                    'Users' {
                        $list = @([PSCustomObject]@{ pk = 11; username = 'awhitfield' })
                        if ($IncludeServiceAccount) { $list += [PSCustomObject]@{ pk = 99; username = 'zz-test-automation' } }
                        return $list
                    }
                    'Groups' {
                        @(
                            [PSCustomObject]@{ pk = 'g-root'; name = 'ZZ-TEST-All Staff'; parents = @() }
                            [PSCustomObject]@{ pk = 'g-leaf'; name = 'ZZ-TEST-Team Platform'; parents = @('g-mid') }
                            [PSCustomObject]@{ pk = 'g-mid'; name = 'ZZ-TEST-Department Engineering'; parents = @('g-root') }
                        )
                    }
                    'Applications' { @([PSCustomObject]@{ pk = 'a1'; pbm_uuid = 'pbm-1'; slug = 'zz-test-payroll'; name = 'ZZ-TEST-Payroll Console' }) }
                    'Providers' { @([PSCustomObject]@{ pk = 5; name = 'ZZ-TEST-Payroll Console Provider' }) }
                    'Entitlements' { @([PSCustomObject]@{ pbm_uuid = 'pbm-e1'; name = 'ZZ-TEST-Administrator'; app_slug = 'zz-test-payroll' }) }
                    'ScopeMappings' { @([PSCustomObject]@{ pk = 'm1'; name = 'ZZ-TEST-Lab Profile' }) }
                    'Outposts' { @([PSCustomObject]@{ pk = '2d9c22e3-bbb1-4671-aebf-9763e109d4e1'; name = 'ZZ-TEST-Edge Proxy' }) }
                    'Certificates' { @([PSCustomObject]@{ pk = 'kp1'; name = 'ZZ-TEST-SAML Signing' }) }
                    'Flows' { @([PSCustomObject]@{ pk = 'f1'; slug = 'zz-test-partner-authentication' }) }
                    'Stages' { @([PSCustomObject]@{ pk = 's1'; name = 'ZZ-TEST-Identify' }) }
                    'Roles' { @([PSCustomObject]@{ pk = 'role-1'; name = 'ZZ-TEST-Lab Operator' }) }
                    'Tokens' { @([PSCustomObject]@{ identifier = 'zz-test-ada-cli' }) }
                    'Invitations' { @([PSCustomObject]@{ pk = 'i1'; name = 'zz-test-forgotten-offer' }) }
                    'Policies' { @([PSCustomObject]@{ pk = 'p1'; name = 'ZZ-TEST-Deny Contractors' }) }
                    'NotificationRules' { @([PSCustomObject]@{ pk = 'r1'; name = 'ZZ-TEST-Lifecycle Watcher' }) }
                    'NotificationTransports' { @([PSCustomObject]@{ pk = 't1'; name = 'ZZ-TEST-Lifecycle Webhook' }) }
                }
            }

            $script:Deleted = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/rbac/roles/') {
                    # The hidden per-user roles Authentik makes: for a seeded user, the service
                    # account, the seeded outpost's own service user, and somebody else's user,
                    # which must never be touched.
                    return @(
                        [PSCustomObject]@{ pk = 'mr-11'; name = 'ak-managed-role--user-11' }
                        [PSCustomObject]@{ pk = 'mr-99'; name = 'ak-managed-role--user-99' }
                        [PSCustomObject]@{ pk = 'mr-55'; name = 'ak-managed-role--user-55' }
                        [PSCustomObject]@{ pk = 'mr-2'; name = 'ak-managed-role--user-2' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/core/users/' -and $Query['username'] -eq 'ak-outpost-2d9c22e3bbb14671aebf9763e109d4e1') {
                    return @([PSCustomObject]@{ pk = 55; username = 'ak-outpost-2d9c22e3bbb14671aebf9763e109d4e1' })
                }
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') {
                    # One binding per target, named after the target so the order is provable.
                    return @([PSCustomObject]@{ pk = "b-$($Query['target'])"; policy = 'p1' })
                }
                if ($Method -eq 'DELETE') { $script:Deleted.Add($Path) }
                return $null
            }
        }
    }

    Context 'WhatIf must win over Force' {

        It 'deletes nothing at all under -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'DELETE' }
            }
        }

        It 'reports nothing removed' {
            InModuleScope TestEnvironment {
                $r = Remove-AuthentikEnvironment -Force -WhatIf -PassThru
                @($r.Users.Removed + $r.Groups.Removed + $r.Applications.Removed + $r.Policies.Removed).Count | Should-Be 0
            }
        }

        It 'does not touch the service account or its record even when asked to' {
            InModuleScope TestEnvironment {
                Mock Remove-Item { }
                $null = Remove-AuthentikEnvironment -Force -WhatIf -RemoveServiceAccount -RemoveCredentialFile

                Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'DELETE' -and $Path -eq '/core/users/99/' }
                Should-NotInvoke Remove-Item
            }
        }
    }

    Context 'Force actually removes, in order' {

        It 'removes the bindings on every seeded target before the policy and the entitlement' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                foreach ($binding in '/policies/bindings/b-pbm-1/', '/policies/bindings/b-pbm-e1/', '/policies/bindings/b-r1/') {
                    $script:Deleted.IndexOf($binding) | Should-BeLessThan $script:Deleted.IndexOf('/policies/all/p1/')
                    $script:Deleted.IndexOf($binding) | Should-BeLessThan $script:Deleted.IndexOf('/core/application_entitlements/pbm-e1/')
                }
            }
        }

        It 'removes invitations and tokens first, entitlements before applications, and roles before groups' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted[0] | Should-Be '/stages/invitation/invitations/i1/'
                $script:Deleted[1] | Should-Be '/core/tokens/zz-test-ada-cli/'
                $script:Deleted.IndexOf('/core/application_entitlements/pbm-e1/') | Should-BeLessThan $script:Deleted.IndexOf('/core/applications/zz-test-payroll/')
                $script:Deleted.IndexOf('/providers/all/5/') | Should-BeLessThan $script:Deleted.IndexOf('/propertymappings/provider/scope/m1/')
                # An outpost holds its providers, so it goes before the application; a
                # certificate is held by a provider, so it goes after.
                $script:Deleted.IndexOf('/outposts/instances/2d9c22e3-bbb1-4671-aebf-9763e109d4e1/') | Should-BeLessThan $script:Deleted.IndexOf('/core/applications/zz-test-payroll/')
                $script:Deleted.IndexOf('/providers/all/5/') | Should-BeLessThan $script:Deleted.IndexOf('/crypto/certificatekeypairs/kp1/')
                # A provider's authorization flow cascades, so the flow goes after the provider;
                # a stage is bound by the flow, so it goes after the flow.
                $script:Deleted.IndexOf('/providers/all/5/') | Should-BeLessThan $script:Deleted.IndexOf('/flows/instances/zz-test-partner-authentication/')
                $script:Deleted.IndexOf('/flows/instances/zz-test-partner-authentication/') | Should-BeLessThan $script:Deleted.IndexOf('/stages/all/s1/')
                $script:Deleted.IndexOf('/rbac/roles/role-1/') | Should-BeLessThan $script:Deleted.IndexOf('/core/groups/g-leaf/')
            }
        }

        It 'removes the application before its provider' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted.IndexOf('/core/applications/zz-test-payroll/') | Should-BeLessThan $script:Deleted.IndexOf('/providers/all/5/')
            }
        }

        It 'removes the leaf group before the group it nests under' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted.IndexOf('/core/groups/g-leaf/') | Should-BeLessThan $script:Deleted.IndexOf('/core/groups/g-mid/')
                $script:Deleted.IndexOf('/core/groups/g-mid/') | Should-BeLessThan $script:Deleted.IndexOf('/core/groups/g-root/')
            }
        }

        It 'removes users before groups and the rule before its transport' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted.IndexOf('/core/users/11/') | Should-BeLessThan $script:Deleted.IndexOf('/core/groups/g-leaf/')
                $script:Deleted.IndexOf('/events/rules/r1/') | Should-BeLessThan $script:Deleted.IndexOf('/events/transports/t1/')
            }
        }

        It 'removes the hidden per-user roles Authentik made for a seeded user and for the outpost''s service user, before them, and nobody else''s' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted.IndexOf('/rbac/roles/mr-11/') | Should-BeLessThan $script:Deleted.IndexOf('/core/users/11/')
                $script:Deleted.IndexOf('/rbac/roles/mr-55/') | Should-BeLessThan $script:Deleted.IndexOf('/outposts/instances/2d9c22e3-bbb1-4671-aebf-9763e109d4e1/')
                $script:Deleted | Should-NotContainCollection @('/rbac/roles/mr-2/')
                $script:Deleted | Should-NotContainCollection @('/rbac/roles/mr-99/')
            }
        }

        It 'reports what it removed per type' {
            InModuleScope TestEnvironment {
                $r = Remove-AuthentikEnvironment -Force -PassThru
                $r.Users.Removed | Should-BeCollection @('awhitfield')
                @($r.Groups.Removed).Count | Should-Be 3
                $r.Providers.Removed | Should-BeCollection @('ZZ-TEST-Payroll Console Provider')
            }
        }
    }

    Context 'The service account' {

        It 'is left alone by default' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted | Should-NotContainCollection @('/core/users/99/')
            }
        }

        It 'is removed last when asked, after the hidden role Authentik made for it' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force -RemoveServiceAccount
                $script:Deleted[$script:Deleted.Count - 1] | Should-Be '/core/users/99/'
                $script:Deleted[$script:Deleted.Count - 2] | Should-Be '/rbac/roles/mr-99/'
            }
        }

        It 'reads the vault pointer out of the record before deleting the file' {
            InModuleScope TestEnvironment {
                $record = Join-Path $TestDrive 'auth.example.com.serviceaccount.json'
                '{"baseUrl":"https://auth.example.com","username":"zz-test-automation","userPk":99,"protection":"SecretStore","vaultName":"AuthentikEnvironment","secretName":"AuthentikEnvironment-auth.example.com-zz-test-automation"}' |
                    Set-Content -LiteralPath $record
                Mock Get-AuthentikCredentialPath { $record }
                Mock Remove-TestVaultSecret { }

                $null = Remove-AuthentikEnvironment -Force -RemoveServiceAccount -RemoveCredentialFile

                Should-Invoke Remove-TestVaultSecret -Times 1 -Exactly -ParameterFilter { $SecretName -like 'AuthentikEnvironment-*' }
                Test-Path -LiteralPath $record | Should-BeFalse
            }
        }
    }

    Context 'Keep' {

        It 'honours -Keep for each type individually' {
            InModuleScope TestEnvironment {
                foreach ($case in @(
                        @{ Keep = 'Invitations'; Path = '/stages/invitation/invitations/i1/' }
                        @{ Keep = 'Tokens'; Path = '/core/tokens/zz-test-ada-cli/' }
                        @{ Keep = 'Bindings'; Path = '/policies/bindings/b-pbm-1/' }
                        @{ Keep = 'Policies'; Path = '/policies/all/p1/' }
                        @{ Keep = 'Entitlements'; Path = '/core/application_entitlements/pbm-e1/' }
                        @{ Keep = 'Outposts'; Path = '/outposts/instances/2d9c22e3-bbb1-4671-aebf-9763e109d4e1/' }
                        @{ Keep = 'Applications'; Path = '/core/applications/zz-test-payroll/' }
                        @{ Keep = 'ScopeMappings'; Path = '/propertymappings/provider/scope/m1/' }
                        @{ Keep = 'Certificates'; Path = '/crypto/certificatekeypairs/kp1/' }
                        @{ Keep = 'Flows'; Path = '/flows/instances/zz-test-partner-authentication/' }
                        @{ Keep = 'Flows'; Path = '/stages/all/s1/' }
                        @{ Keep = 'Roles'; Path = '/rbac/roles/role-1/' }
                        @{ Keep = 'Users'; Path = '/core/users/11/' }
                        @{ Keep = 'Groups'; Path = '/core/groups/g-root/' }
                        @{ Keep = 'NotificationRules'; Path = '/events/rules/r1/' }
                    )) {
                    $script:Deleted.Clear()
                    $null = Remove-AuthentikEnvironment -Force -Keep $case.Keep
                    $expectedPath = $case.Path
                    $script:Deleted | Should-NotContainCollection @($expectedPath)
                    $script:Deleted.Count | Should-BeGreaterThan 0
                }
            }
        }

        It 'keeps the provider along with its application' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force -Keep Applications
                $script:Deleted | Should-NotContainCollection @('/providers/all/5/')
            }
        }
    }
}
