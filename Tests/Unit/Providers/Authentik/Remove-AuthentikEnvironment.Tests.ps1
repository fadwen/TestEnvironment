#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown is the destructive half of the module, and the property that matters most is
    that -WhatIf wins over -Force: -Force defeating -WhatIf was the worst defect an earlier
    module shipped, and it is pinned here first. After that, the order - bindings before
    policies, applications before their providers, leaf groups before their parents, rules
    before their transports - and the promise that the service account is left alone unless
    asked for, and removed last when it is.
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
                    'Policies' { @([PSCustomObject]@{ pk = 'p1'; name = 'ZZ-TEST-Deny Contractors' }) }
                    'NotificationRules' { @([PSCustomObject]@{ pk = 'r1'; name = 'ZZ-TEST-Lifecycle Watcher' }) }
                    'NotificationTransports' { @([PSCustomObject]@{ pk = 't1'; name = 'ZZ-TEST-Lifecycle Webhook' }) }
                }
            }

            $script:Deleted = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') { return @([PSCustomObject]@{ pk = 'b1'; policy = 'p1' }) }
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

        It 'removes the binding before the policy' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force
                $script:Deleted.IndexOf('/policies/bindings/b1/') | Should-BeLessThan $script:Deleted.IndexOf('/policies/all/p1/')
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

        It 'is removed last when asked' {
            InModuleScope TestEnvironment {
                $null = Remove-AuthentikEnvironment -Force -RemoveServiceAccount
                $script:Deleted[$script:Deleted.Count - 1] | Should-Be '/core/users/99/'
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
                        @{ Keep = 'Policies'; Path = '/policies/all/p1/' }
                        @{ Keep = 'Applications'; Path = '/core/applications/zz-test-payroll/' }
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
