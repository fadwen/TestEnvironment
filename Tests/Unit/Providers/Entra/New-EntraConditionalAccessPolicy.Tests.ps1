#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A Conditional Access policy is the one object this module creates that can deny a real
    person access to a real account, so these tests are about what the function refuses to do
    rather than what it produces.

    Two of them are regressions from the first live run:

    - includeLocations was serialised as the string "All" rather than the array ["All"],
      because assigning the result of an if expression unrolls a single-element array. Graph
      rejected it with error 1007, "does not match the schema of ConditionalAccessPolicy
      type", naming no field - which reads exactly like a transient failure and is not one.
    - The seeded rule (user.userType -eq "Guest") pulled two real external accounts into a
      seeded group on a live tenant, which is what the group tests now pin.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraConditionalAccessPolicy' -Tag 'Unit', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:EntraConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                TenantName     = 'Contoso'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            # Every policy body the function would send, captured instead of sent. Nothing in
            # this file reaches a tenant.
            $script:SentBodies = [System.Collections.Generic.List[object]]::new()

            # A default first, so a lookup the function gains later cannot fail the whole file
            # with "no mock matched" instead of the assertion under test. An empty result means
            # nothing already exists, which is the state these tests are describing.
            Mock Get-EntraSeededObject { @() }

            Mock Get-EntraSeededObject {
                @([PSCustomObject]@{ id = 'loc-country'; displayName = 'ENTRALAB-Permitted Countries' }
                    [PSCustomObject]@{ id = 'loc-corp'; displayName = 'ENTRALAB-Corporate Egress' }
                    [PSCustomObject]@{ id = 'loc-suspect'; displayName = 'ENTRALAB-Suspect Range' }
                    [PSCustomObject]@{ id = 'loc-host'; displayName = 'ENTRALAB-Single Host Egress' })
            } -ParameterFilter { $Type -eq 'NamedLocations' }

            # Applications carry an appId distinct from the directory object id, because that is
            # the identifier Conditional Access names. The two differ here on purpose: a policy
            # built with the object id would match nothing, and this is what catches that.
            Mock Get-EntraSeededObject {
                @([PSCustomObject]@{ id = 'obj-assigned'; appId = 'appid-assigned'; displayName = 'ENTRALAB-Expense Portal' }
                    [PSCustomObject]@{ id = 'obj-direct'; appId = 'appid-direct'; displayName = 'ENTRALAB-Payroll Console' }
                    [PSCustomObject]@{ id = 'obj-groups'; appId = 'appid-groups'; displayName = 'ENTRALAB-Engineering Wiki' })
            } -ParameterFilter { $Type -eq 'Applications' }

            Mock Resolve-EntraSeededId { "group-$Key" }

            Mock Invoke-EntraRequest {
                if ($Path -like '*authenticationStrength*') {
                    return [PSCustomObject]@{ value = @(
                            [PSCustomObject]@{ id = 'strength-1'; displayName = 'Phishing-resistant MFA' }) }
                }
                if ($Method -eq 'POST' -and $Path -eq '/identity/conditionalAccess/policies') {
                    $script:SentBodies.Add($Body)
                    return [PSCustomObject]@{ id = "policy-$($script:SentBodies.Count)"; state = $Body.state }
                }
                return $null
            }
        }
    }

    It 'never creates an enforcing policy, whatever the data asks for' {
        # The invariant, stated as what it actually protects. It used to read "every policy is
        # report-only", which was true while report-only was the only state the data could
        # produce. The seed data now also carries one disabled policy, because real tenants keep
        # retired ones and an inventory script must not count them as active - and disabled is
        # strictly quieter than report-only, which still logs.
        #
        # What must never appear is 'enabled'. That is the whole rule.
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy | Out-Null

            $script:SentBodies.Count | Should-BeGreaterThan 0
            foreach ($body in $script:SentBodies) {
                @('enabledForReportingButNotEnforced', 'disabled') |
                    Should-ContainCollection @($body.state)
            }
        }
    }

    It 'refuses a policy whose data asks for any other state' {
        # A typo in the State column must not become an enforcing policy in a tenant somebody
        # uses. The refusal is per policy, so the rest of the seed still runs.
        InModuleScope TestEnvironment {
            # A passthrough default, so the function's other seed lookups still return the real
            # data and this test fails on the state alone rather than on a missing mock.
            Mock Get-EntraSeedData {
                Import-Csv -LiteralPath (Join-Path $script:TestEnvironmentProvider['Entra'].DataPath "$Name.csv") -Encoding UTF8
            }

            Mock Get-EntraSeedData {
                @([PSCustomObject]@{
                        Key = 'ca-typo'; DisplayName = 'Typo'; IncludeGroups = 'all-staff'
                        ExcludeGroups = ''; ExcludeUsers = ''; IncludeApplications = 'All'
                        ClientAppTypes = 'browser'; IncludePlatforms = ''; IncludeLocations = ''
                        ExcludeLocations = ''; SignInRiskLevels = ''; UserRiskLevels = ''
                        GrantControls = 'mfa'; GrantOperator = 'OR'; SessionControls = ''
                        State = 'enabled'; Purpose = 'a typo'
                    })
            } -ParameterFilter { $Name -eq 'EntraConditionalAccessPolicies' }

            New-EntraConditionalAccessPolicy -ErrorAction SilentlyContinue | Out-Null

            @($script:SentBodies | Where-Object { $_.state -eq 'enabled' }).Count | Should-Be 0
        }
    }

    It 'exposes no parameter that could enable a policy' {
        # The safety property is that this is not configurable. A -State parameter appearing
        # later would make enforcement one keystroke away in a tenant that is in real use.
        $command = Get-Command New-EntraConditionalAccessPolicy
        $command.Parameters.Keys | Should-NotContainCollection @('State')
        $command.Parameters.Keys | Should-NotContainCollection @('Enabled')
        $command.Parameters.Keys | Should-NotContainCollection @('Enforce')
    }

    It 'never scopes a policy to all users' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy | Out-Null

            foreach ($body in $script:SentBodies) {
                @($body.conditions.users.includeGroups).Count | Should-BeGreaterThan 0
                @($body.conditions.users.includeUsers) | Should-NotContainCollection @('All')
            }
        }
    }

    It 'refuses to create a policy whose groups do not resolve' {
        InModuleScope TestEnvironment {
            # An unscoped Conditional Access policy applies tenant-wide, so a policy that
            # resolves nothing must not be created rather than created broadly.
            Mock Resolve-EntraSeededId { $null }

            New-EntraConditionalAccessPolicy -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

            $script:SentBodies.Count | Should-Be 0
        }
    }

    It 'sends includeLocations as an array, not as a bare string' {
        InModuleScope TestEnvironment {
            # The regression. PowerShell unrolls a single-element array assigned from an if
            # expression, and Graph then rejects the whole policy with a schema error that
            # names no field.
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-geo-block' | Out-Null

            $script:SentBodies.Count | Should-Be 1
            $locations = $script:SentBodies[0].conditions.locations

            # Tested without piping: the pipeline unwraps a single-item collection to its one
            # element, so piping into a type assertion would report [string] for a correct
            # single-element array and fail for the wrong reason.
            ($locations.includeLocations -is [System.Array]) | Should-BeTrue
            @($locations.includeLocations).Count | Should-Be 1
            @($locations.includeLocations)[0] | Should-Be 'All'
        }
    }

    It 'survives a round trip through ConvertTo-Json as an array' {
        InModuleScope TestEnvironment {
            # The assertion that would actually have caught the bug: the defect was only
            # visible in the serialised body, not in the hashtable.
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-geo-block' | Out-Null

            $json = $script:SentBodies[0] | ConvertTo-Json -Depth 20 -Compress
            $json | Should-MatchString '"includeLocations":\["All"\]'
            $json | Should-NotMatchString '"includeLocations":"All"'
        }
    }

    It 'inverts a country condition by excluding it from everywhere' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-geo-block' | Out-Null

            $locations = $script:SentBodies[0].conditions.locations
            @($locations.excludeLocations) | Should-BeCollection @('loc-country')
        }
    }

    It 'resolves an authentication strength by name rather than by hardcoded id' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-strength-phish' | Out-Null

            $script:SentBodies[0].grantControls.authenticationStrength.id | Should-Be 'strength-1'
        }
    }

    It 'falls back to a plain MFA grant when the tenant has no matching strength' {
        InModuleScope TestEnvironment {
            # Losing the control entirely would produce a policy granting nothing, which
            # Graph accepts and which means something quite different.
            Mock Invoke-EntraRequest {
                if ($Path -like '*authenticationStrength*') { return [PSCustomObject]@{ value = @() } }
                if ($Method -eq 'POST' -and $Path -eq '/identity/conditionalAccess/policies') {
                    $script:SentBodies.Add($Body)
                    return [PSCustomObject]@{ id = 'p'; state = $Body.state }
                }
                return $null
            }

            New-EntraConditionalAccessPolicy -PolicyKey 'ca-strength-phish' -WarningAction SilentlyContinue | Out-Null

            @($script:SentBodies[0].grantControls.builtInControls) | Should-ContainCollection @('mfa')
        }
    }

    It 'preserves the AND operator, where satisfying one control is not enough' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-and-operator' | Out-Null

            $script:SentBodies[0].grantControls.operator | Should-Be 'AND'
            @($script:SentBodies[0].grantControls.builtInControls).Count | Should-Be 2
        }
    }

    It 'builds a session-controls-only policy with no grant control at all' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy -PolicyKey 'ca-session-limit' | Out-Null

            $body = $script:SentBodies[0]
            $body.ContainsKey('grantControls') | Should-BeFalse
            $body.sessionControls.signInFrequency.value | Should-Be 4
            $body.sessionControls.signInFrequency.type | Should-Be 'hours'
            $body.sessionControls.persistentBrowser.mode | Should-Be 'never'
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy -WhatIf | Out-Null
            $script:SentBodies.Count | Should-Be 0
        }
    }

    It 'names the prefix on every policy it creates' {
        InModuleScope TestEnvironment {
            New-EntraConditionalAccessPolicy | Out-Null

            foreach ($body in $script:SentBodies) {
                $body.displayName | Should-MatchString '^ENTRALAB-'
            }
        }
    }
}
