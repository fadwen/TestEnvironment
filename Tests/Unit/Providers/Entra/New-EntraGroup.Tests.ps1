#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The dynamic membership guard is the reason this file exists.

    A dynamic group is the one object this module creates that reaches out and claims things
    the module did not create. On the first live run the rule was
    (user.userType -eq "Guest"), and Entra immediately put two real external accounts into a
    seeded group. Nothing was granted to them and nothing broke, but a seeded group silently
    containing real people is precisely the blast radius the module exists to avoid.

    The guard is belt and braces with the contract test: that one checks the shipped CSV, this
    one checks that the code refuses a rule regardless of where it came from.

    Creation is batched now, so the assertions read the request bodies handed to
    Invoke-EntraBatch rather than to Invoke-EntraRequest.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraGroup' -Tag 'Unit', 'Safety' {

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

            $script:CreateBodies = [System.Collections.Generic.List[object]]::new()
            $script:MemberRefs = [System.Collections.Generic.List[object]]::new()
            $script:Placed = [System.Collections.Generic.List[object]]::new()

            # Seeded users, so membership can resolve without reaching a tenant.
            Mock Get-EntraSeededObject {
                if ($Type -eq 'Users') {
                    return @('jnino', 'zmueller', 'mbell', 'ofitzgerald', 'praghunathan', 'talvarez',
                        'hkobayashi', 'awhitfield', 'svcreporting' | ForEach-Object {
                            [PSCustomObject]@{ id = "user-$_"; userPrincipalName = "ENTRALAB-$_@contoso.onmicrosoft.com" }
                        })
                }
                if ($Type -eq 'AdministrativeUnits') {
                    return @([PSCustomObject]@{ id = 'au-groups'; displayName = 'ENTRALAB-Groups' })
                }
                return @()
            }

            Mock Add-EntraUnitMember {
                foreach ($id in $ObjectId) { $script:Placed.Add($id) }
                return @($ObjectId).Count
            }

            # Batch is the seam now. Requests are recorded and answered with a synthetic id,
            # so nothing reaches a tenant and the bodies stay inspectable.
            Mock Invoke-EntraBatch {
                $index = 0
                @(foreach ($item in $Request) {
                        $index++
                        if ($item.Url -eq '/groups') { $script:CreateBodies.Add($item.Body) }
                        elseif ($item.Url -like '*/members/$ref') { $script:MemberRefs.Add($item) }

                        [PSCustomObject]@{
                            PSTypeName = 'EntraBatchResult'
                            Reference  = $item.Reference
                            Success    = $true
                            Status     = 201
                            Body       = [PSCustomObject]@{ id = "created-$($item.Reference)" }
                            Error      = $null
                        }
                    })
            }

            # A backstop: nothing in this file may reach the network.
            Mock Invoke-EntraRequest { throw "A unit test attempted a real Graph call: $Method $Path" }
        }
    }

    Context 'Dynamic membership' {

        It 'substitutes the connection prefix into the rule' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'dyn-engineering' -SkipMembership | Out-Null

                $script:CreateBodies.Count | Should-Be 1
                $script:CreateBodies[0].membershipRule | Should-MatchString 'ENTRALAB-'
                $script:CreateBodies[0].membershipRule | Should-NotMatchString '\{Prefix\}'
            }
        }

        It 'refuses a rule that does not scope itself to the prefix' {
            InModuleScope TestEnvironment {
                # The regression, at the code level. A rule reaching every guest in the
                # directory must not be creatable even if the data says so.
                Mock Get-EntraSeedData {
                    @([PSCustomObject]@{
                            Key = 'dyn-danger'; DisplayName = 'Dangerous'; GroupKind = 'Security'
                            MembershipType = 'Dynamic'; MembershipRule = '(user.userType -eq "Guest")'
                            Members = ''; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'unsafe'
                        })
                }

                New-EntraGroup -ErrorAction SilentlyContinue | Out-Null

                $script:CreateBodies.Count | Should-Be 0
            }
        }

        It 'marks the rule processing state On, so membership actually evaluates' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'dyn-engineering' -SkipMembership | Out-Null
                $script:CreateBodies[0].membershipRuleProcessingState | Should-Be 'On'
            }
        }

        It 'adds DynamicMembership without displacing the flavour groupTypes' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'dyn-engineering' -SkipMembership | Out-Null
                @($script:CreateBodies[0].groupTypes) | Should-ContainCollection @('DynamicMembership')
            }
        }

        It 'assigns no members by hand, because Entra owns that membership' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'dyn-engineering' | Out-Null
                $script:MemberRefs.Count | Should-Be 0
            }
        }
    }

    Context 'Group flavours' {

        It 'creates a security group as security-enabled and not mail-enabled' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'dept-engineering' -SkipMembership | Out-Null

                $script:CreateBodies[0].securityEnabled | Should-BeTrue
                $script:CreateBodies[0].mailEnabled | Should-BeFalse
            }
        }

        It 'creates a Microsoft 365 group as Unified and mail-enabled' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'm365-collab' -SkipMembership | Out-Null

                @($script:CreateBodies[0].groupTypes) | Should-ContainCollection @('Unified')
                $script:CreateBodies[0].mailEnabled | Should-BeTrue
            }
        }

        It 'sets isAssignableToRole only where the data asks for it' {
            InModuleScope TestEnvironment {
                # Immutable after creation, so getting it wrong means deleting and rebuilding.
                New-EntraGroup -GroupKey 'role-support' -SkipMembership | Out-Null
                $script:CreateBodies[0].isAssignableToRole | Should-BeTrue

                $script:CreateBodies.Clear()
                New-EntraGroup -GroupKey 'dept-it' -SkipMembership | Out-Null
                $script:CreateBodies[0].ContainsKey('isAssignableToRole') | Should-BeFalse
            }
        }

        It 'refuses a group kind Graph cannot create' {
            InModuleScope TestEnvironment {
                # Verified live: Graph refuses distribution lists and mail-enabled security
                # groups outright, whatever combination of flags is sent. The guard is written
                # before the switch, because 'continue' inside a switch breaks the switch
                # rather than the enclosing foreach and the group gets created anyway.
                Mock Get-EntraSeedData {
                    @([PSCustomObject]@{
                            Key = 'dl'; DisplayName = 'Announcements'; GroupKind = 'Distribution'
                            MembershipType = 'Assigned'; MembershipRule = ''
                            Members = ''; MemberGroups = ''; IsAssignableToRole = 'FALSE'; Tier = 'Core'; Purpose = 'x'
                        })
                }

                New-EntraGroup -ErrorAction SilentlyContinue | Out-Null
                $script:CreateBodies.Count | Should-Be 0
            }
        }
    }

    Context 'Ownership marker' {

        It 'writes the seed tag into the description, which teardown requires' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'empty-hold' -SkipMembership | Out-Null
                ([string]$script:CreateBodies[0].description) | Should-MatchString 'ENTRALAB-seed'
            }
        }

        It 'prefixes the display name' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'empty-hold' -SkipMembership | Out-Null
                ([string]$script:CreateBodies[0].displayName) | Should-MatchString '^ENTRALAB-'
            }
        }

        It 'places every created group in the Groups administrative unit' {
            InModuleScope TestEnvironment {
                # Containment is what teardown treats as proof, so a step that creates groups
                # and does not place them has done half its job.
                New-EntraGroup -GroupKey 'empty-hold', 'dept-it' -SkipMembership | Out-Null
                $script:Placed.Count | Should-Be 2
            }
        }
    }

    Context 'Membership' {

        It 'nests a group inside another group' {
            InModuleScope TestEnvironment {
                New-EntraGroup -GroupKey 'nested-tier2', 'nested-tier3' | Out-Null

                # Tier 2 holds Tier 3 and no users of its own; Tier 3 holds two users.
                $nesting = @($script:MemberRefs | Where-Object { $_.Body.'@odata.id' -like '*created-nested-tier3' })
                $nesting.Count | Should-Be 1
            }
        }

        It 'skips a member naming an object that does not exist' {
            InModuleScope TestEnvironment {
                Mock Get-EntraSeededObject {
                    if ($Type -eq 'AdministrativeUnits') { return @([PSCustomObject]@{ id = 'au-groups'; displayName = 'ENTRALAB-Groups' }) }
                    return @()
                }

                New-EntraGroup -GroupKey 'dept-engineering' -WarningAction SilentlyContinue | Out-Null

                # The group is still created; only its unresolvable members are dropped.
                $script:CreateBodies.Count | Should-Be 1
                $script:MemberRefs.Count | Should-Be 0
            }
        }

        It 'creates nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                New-EntraGroup -WhatIf | Out-Null
                $script:CreateBodies.Count | Should-Be 0
            }
        }
    }
}
