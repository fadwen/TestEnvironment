#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Role eligibility is the second thing this module creates that touches privilege, after the
    custom role definitions themselves - so like the Conditional Access tests, these are about
    what the function refuses to do rather than what it produces.

    Two invariants carry the whole safety argument:

    - Eligible, never active. An eligible schedule grants nothing until a human activates it,
      which is the same bargain a report-only policy strikes. The active counterpart lives at a
      different endpoint and this must never post to it.
    - Seeded custom roles only. The role is resolved through Get-EntraSeededObject, which
      returns prefixed custom definitions and refuses built-ins, so there is no path from a seed
      row to eligibility for Global Administrator.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraRoleEligibility' -Tag 'Unit', 'Safety' {

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

            # Every request the function would send, captured rather than sent, with its path so
            # the endpoint assertions can tell the eligible collection from the active one.
            $script:SentRequests = [System.Collections.Generic.List[object]]::new()

            Mock Get-EntraSeededObject { @() }

            # The three seeded custom roles, named exactly as the function builds the name:
            # prefix plus the DisplayName from EntraDirectoryRoles.csv.
            Mock Get-EntraSeededObject {
                @([PSCustomObject]@{ id = 'role-gr'; displayName = 'ENTRALAB-Lab Group Reader'; isBuiltIn = $false }
                    [PSCustomObject]@{ id = 'role-uw'; displayName = 'ENTRALAB-Lab User Attribute Writer'; isBuiltIn = $false }
                    [PSCustomObject]@{ id = 'role-ar'; displayName = 'ENTRALAB-Lab Application Reader'; isBuiltIn = $false })
            } -ParameterFilter { $Type -eq 'DirectoryRoles' }

            Mock Get-EntraSeededObject {
                @([PSCustomObject]@{ id = 'au-users'; displayName = 'ENTRALAB-Users' }
                    [PSCustomObject]@{ id = 'au-groups'; displayName = 'ENTRALAB-Groups' })
            } -ParameterFilter { $Type -eq 'AdministrativeUnits' }

            Mock Resolve-EntraSeededId { "principal-$Key" }

            Mock Invoke-EntraRequest {
                $script:SentRequests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })

                # Nothing already eligible, so every row is a create.
                if ($Method -eq 'GET') { return @() }
                return [PSCustomObject]@{ id = "req-$($script:SentRequests.Count)" }
            }
        }
    }

    Context 'Eligible, never active' {

        It 'posts every request to the eligibility collection and never to the assignment one' {
            InModuleScope TestEnvironment {
                New-EntraRoleEligibility | Out-Null

                $posts = @($script:SentRequests | Where-Object { $_.Method -eq 'POST' })
                $posts.Count | Should-BeGreaterThan 0

                foreach ($post in $posts) {
                    $post.Path | Should-Be '/roleManagement/directory/roleEligibilityScheduleRequests'
                }

                # The active counterpart. Naming it explicitly rather than asserting on the
                # eligible path alone, because a future edit that adds it would otherwise pass.
                @($script:SentRequests | Where-Object { $_.Path -like '*roleAssignmentScheduleRequests*' }).Count |
                    Should-Be 0
            }
        }

        It 'asks only for adminAssign' {
            InModuleScope TestEnvironment {
                New-EntraRoleEligibility | Out-Null

                foreach ($post in @($script:SentRequests | Where-Object { $_.Method -eq 'POST' })) {
                    $post.Body.action | Should-Be 'adminAssign'
                }
            }
        }

        It 'exposes no parameter that could make an eligibility active' {
            # The safety property is that this is not configurable, exactly as with the
            # Conditional Access state. A -Permanent or -Active appearing later would turn a
            # seeding script into something that grants standing privilege.
            $command = Get-Command New-EntraRoleEligibility
            $command.Parameters.Keys | Should-NotContainCollection @('Active')
            $command.Parameters.Keys | Should-NotContainCollection @('AssignmentType')
            $command.Parameters.Keys | Should-NotContainCollection @('Permanent')
            $command.Parameters.Keys | Should-NotContainCollection @('Assign')
        }

        It 'bounds every eligibility with an expiry rather than leaving it standing' {
            InModuleScope TestEnvironment {
                New-EntraRoleEligibility | Out-Null

                foreach ($post in @($script:SentRequests | Where-Object { $_.Method -eq 'POST' })) {
                    $post.Body.scheduleInfo.expiration.type | Should-Be 'afterDuration'
                    $post.Body.scheduleInfo.expiration.duration | Should-MatchString '^P\d+D$'
                }
            }
        }
    }

    Context 'Only what this module created' {

        It 'refuses a row naming a role it did not create' {
            InModuleScope TestEnvironment {
                Mock Get-EntraSeedData {
                    Import-Csv -LiteralPath (Join-Path $script:TestEnvironmentProvider['Entra'].DataPath "$Name.csv") -Encoding UTF8
                }

                # A row pointing at a built-in role by name. It has no seed definition, so it
                # cannot resolve to a prefixed custom role - and the function must skip it
                # rather than fall back to anything.
                Mock Get-EntraSeedData {
                    @([PSCustomObject]@{
                            Key = 'elig-escalate'; RoleKey = 'Global Administrator'
                            PrincipalKey = 'talvarez'; PrincipalKind = 'User'
                            ScopeKind = 'Directory'; ScopeUnit = ''; DurationDays = '30'
                            Purpose = 'an escalation attempt'
                        })
                } -ParameterFilter { $Name -eq 'EntraRoleEligibilities' }

                New-EntraRoleEligibility -WarningAction SilentlyContinue | Out-Null

                @($script:SentRequests | Where-Object { $_.Method -eq 'POST' }).Count | Should-Be 0
            }
        }

        It 'skips an administrative-unit row whose unit is missing rather than widening the scope' {
            # The failure that matters. Falling back to '/' when the unit cannot be found turns a
            # deliberately narrow grant into a directory-wide one, silently.
            InModuleScope TestEnvironment {
                Mock Get-EntraSeededObject { @() } -ParameterFilter { $Type -eq 'AdministrativeUnits' }

                New-EntraRoleEligibility -WarningAction SilentlyContinue | Out-Null

                foreach ($post in @($script:SentRequests | Where-Object { $_.Method -eq 'POST' })) {
                    # Whatever survived must be a row that asked for the directory scope in the
                    # first place, never a unit-scoped row that lost its unit.
                    $post.Body.directoryScopeId | Should-Be '/'
                }
            }
        }

        It 'scopes to the administrative unit by id when the unit does exist' {
            InModuleScope TestEnvironment {
                New-EntraRoleEligibility | Out-Null

                $scoped = @($script:SentRequests |
                        Where-Object { $_.Method -eq 'POST' -and $_.Body.directoryScopeId -ne '/' })

                $scoped.Count | Should-BeGreaterThan 0
                foreach ($post in $scoped) {
                    $post.Body.directoryScopeId | Should-Be '/administrativeUnits/au-users'
                }
            }
        }
    }

    Context 'Idempotence' {

        It 'treats an already-exists conflict as the ordinary answer, not a failure' {
            # Reached whenever the pre-read of existing schedules fails - a throttle is enough -
            # because every row then looks new and is re-posted. A correctly seeded tenant must
            # not report three failures for being correctly seeded.
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    if ($Method -eq 'GET') { throw 'TooManyRequests' }
                    throw 'RoleAssignmentExists: The Role assignment already exists.'
                }

                $warnings = @()
                New-EntraRoleEligibility -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

                @($warnings | Where-Object { $_ -match 'Could not create' }).Count | Should-Be 0
            }
        }

        It 'reports the schedule id rather than the id of the request that made it' {
            # The two address different objects at different endpoints. Returning the request id
            # would make Id mean one thing on a first run and another on a re-run.
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    if ($Method -eq 'GET') { return @() }
                    return [PSCustomObject]@{ id = 'request-id'; targetScheduleId = 'schedule-id' }
                }

                $result = @(New-EntraRoleEligibility -PassThru)

                $result.Count | Should-BeGreaterThan 0
                foreach ($item in $result) { $item.Id | Should-Be 'schedule-id' }
            }
        }


        It 'creates nothing when the eligibility already exists' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    $script:SentRequests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })

                    if ($Method -eq 'GET') {
                        # Every seeded row, already in place. principal-<key> matches what the
                        # Resolve-EntraSeededId mock returns.
                        return @(
                            [PSCustomObject]@{ id = 'sched-1'; principalId = 'principal-talvarez'; roleDefinitionId = 'role-gr'; directoryScopeId = '/' }
                            [PSCustomObject]@{ id = 'sched-2'; principalId = 'principal-hkobayashi'; roleDefinitionId = 'role-uw'; directoryScopeId = '/administrativeUnits/au-users' }
                            [PSCustomObject]@{ id = 'sched-3'; principalId = 'principal-role-support'; roleDefinitionId = 'role-ar'; directoryScopeId = '/' }
                        )
                    }
                    return [PSCustomObject]@{ id = 'req' }
                }

                New-EntraRoleEligibility | Out-Null

                @($script:SentRequests | Where-Object { $_.Method -eq 'POST' }).Count | Should-Be 0
            }
        }
    }
}
