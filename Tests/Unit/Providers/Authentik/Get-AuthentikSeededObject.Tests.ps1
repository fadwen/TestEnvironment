#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Ownership is the property teardown rests on. Every object type has a name that carries
    the prefix, and a name alone is not evidence: an administrator can name a group anything.
    These tests give the discovery helper objects that carry the prefix and lack the proof,
    and objects that carry the proof under a different name, and assert that neither is
    claimed. The service account is the one seeded user that must be excluded by default.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AuthentikSeededObject' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            $script:Tagged = [PSCustomObject]@{ labSeedTag = 'ZZ-TEST-seed' }
            $script:Untagged = [PSCustomObject]@{ other = 'x' }
        }
    }

    It 'claims a user only when it is under the seed path and carries the tag' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ pk = 1; username = 'awhitfield'; path = 'zz-test'; attributes = $script:Tagged }
                    [PSCustomObject]@{ pk = 2; username = 'stranger'; path = 'zz-test'; attributes = $script:Untagged }
                    [PSCustomObject]@{ pk = 3; username = 'zz-test-automation'; path = 'zz-test'; attributes = $script:Tagged }
                )
            }

            $users = @(Get-AuthentikSeededObject -Type Users)

            $users.username | Should-BeCollection @('awhitfield')
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/core/users/' -and $Query['path'] -eq 'zz-test' }
        }
    }

    It 'includes the service account only when asked' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @([PSCustomObject]@{ pk = 3; username = 'zz-test-automation'; path = 'zz-test'; attributes = $script:Tagged })
            }

            @(Get-AuthentikSeededObject -Type Users).Count | Should-Be 0
            @(Get-AuthentikSeededObject -Type Users -IncludeServiceAccount).username | Should-BeCollection @('zz-test-automation')
        }
    }

    It 'claims a group only with both the prefix and the tag' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ pk = 'g1'; name = 'ZZ-TEST-All Staff'; attributes = $script:Tagged }
                    [PSCustomObject]@{ pk = 'g2'; name = 'ZZ-TEST-Real Admins'; attributes = $script:Untagged }
                    [PSCustomObject]@{ pk = 'g3'; name = 'Finance'; attributes = $script:Tagged }
                )
            }

            @(Get-AuthentikSeededObject -Type Groups).name | Should-BeCollection @('ZZ-TEST-All Staff')
        }
    }

    It 'claims an application only with the slug prefix and the marker in its description' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ slug = 'zz-test-wiki'; name = 'ZZ-TEST-Engineering Wiki'; meta_description = 'The wiki [ZZ-TEST-seed]' }
                    [PSCustomObject]@{ slug = 'zz-test-lookalike'; name = 'ZZ-TEST-Lookalike'; meta_description = 'Not ours' }
                    [PSCustomObject]@{ slug = 'grafana'; name = 'Grafana'; meta_description = 'copied text [ZZ-TEST-seed]' }
                )
            }

            @(Get-AuthentikSeededObject -Type Applications).slug | Should-BeCollection @('zz-test-wiki')
        }
    }

    It 'claims a provider only when it is unattached or attached to a seeded application' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Path -eq '/core/applications/') {
                    return @([PSCustomObject]@{ slug = 'zz-test-wiki'; name = 'x'; meta_description = '[ZZ-TEST-seed]' })
                }
                @(
                    [PSCustomObject]@{ pk = 1; name = 'ZZ-TEST-Engineering Wiki Provider'; assigned_application_slug = 'zz-test-wiki' }
                    [PSCustomObject]@{ pk = 2; name = 'ZZ-TEST-Orphan Provider'; assigned_application_slug = $null }
                    [PSCustomObject]@{ pk = 3; name = 'ZZ-TEST-Hijacked Provider'; assigned_application_slug = 'grafana' }
                    [PSCustomObject]@{ pk = 4; name = 'Grafana Provider'; assigned_application_slug = $null }
                )
            }

            @(Get-AuthentikSeededObject -Type Providers).pk | Should-BeCollection @(1, 2)
        }
    }

    It 'claims an entitlement only on a seeded application, with the prefix and the tag' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Path -eq '/core/applications/') {
                    return @([PSCustomObject]@{ pk = 'app-1'; slug = 'zz-test-wiki'; name = 'x'; meta_description = '[ZZ-TEST-seed]' })
                }
                if ($Path -eq '/core/application_entitlements/') {
                    $Query['app'] | Should-Be 'app-1'
                    return @(
                        [PSCustomObject]@{ pbm_uuid = 'e1'; name = 'ZZ-TEST-Editor'; attributes = $script:Tagged }
                        [PSCustomObject]@{ pbm_uuid = 'e2'; name = 'ZZ-TEST-Lookalike'; attributes = $script:Untagged }
                        [PSCustomObject]@{ pbm_uuid = 'e3'; name = 'Reader'; attributes = $script:Tagged }
                    )
                }
                @()
            }

            $entitlements = @(Get-AuthentikSeededObject -Type Entitlements)
            $entitlements.pbm_uuid | Should-BeCollection @('e1')
            $entitlements[0].app_slug | Should-Be 'zz-test-wiki'
        }
    }

    It 'claims a token only with the slug prefix and a seeded owner' {
        InModuleScope TestEnvironment {
            $seeded = [PSCustomObject]@{ path = 'zz-test'; attributes = $script:Tagged }
            $stranger = [PSCustomObject]@{ path = 'users'; attributes = $script:Untagged }
            $automation = [PSCustomObject]@{ path = 'zz-test'; username = 'zz-test-automation'; attributes = $script:Tagged }
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ identifier = 'zz-test-ada-cli'; user_obj = $seeded }
                    [PSCustomObject]@{ identifier = 'zz-test-lookalike'; user_obj = $stranger }
                    [PSCustomObject]@{ identifier = 'real-token'; user_obj = $seeded }
                    [PSCustomObject]@{ identifier = 'zz-test-automation-api'; user_obj = $automation }
                )
            }

            # The service account's own token is the credential doing the work. Claiming it
            # would have teardown delete it in the tokens step and strand every step after.
            @(Get-AuthentikSeededObject -Type Tokens).identifier | Should-BeCollection @('zz-test-ada-cli')
            @(Get-AuthentikSeededObject -Type Tokens -IncludeServiceAccount).identifier | Should-BeCollection @('zz-test-ada-cli', 'zz-test-automation-api')
        }
    }

    It 'claims an invitation only with the slug prefix and the tag in its fixed data' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ pk = 'i1'; name = 'zz-test-new-hire'; fixed_data = $script:Tagged }
                    [PSCustomObject]@{ pk = 'i2'; name = 'zz-test-lookalike'; fixed_data = $script:Untagged }
                    [PSCustomObject]@{ pk = 'i3'; name = 'onboarding'; fixed_data = $script:Tagged }
                )
            }

            @(Get-AuthentikSeededObject -Type Invitations).pk | Should-BeCollection @('i1')
        }
    }

    It 'claims a scope mapping by prefix only when it is unmanaged' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ pk = 'm1'; name = 'ZZ-TEST-Lab Profile'; managed = $null }
                    [PSCustomObject]@{ pk = 'm2'; name = 'ZZ-TEST-Managed Lookalike'; managed = 'goauthentik.io/providers/oauth2/scope-openid' }
                    [PSCustomObject]@{ pk = 'm3'; name = 'authentik default OAuth Mapping: OpenID'; managed = $null }
                )
            }

            @(Get-AuthentikSeededObject -Type ScopeMappings).pk | Should-BeCollection @('m1')
        }
    }

    It 'claims an outpost or a certificate by prefix only when it is unmanaged' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @(
                    [PSCustomObject]@{ pk = 'o1'; name = 'ZZ-TEST-Edge Proxy'; managed = $null }
                    [PSCustomObject]@{ pk = 'o2'; name = 'ZZ-TEST-Embedded Lookalike'; managed = 'goauthentik.io/outposts/embedded' }
                    [PSCustomObject]@{ pk = 'o3'; name = 'authentik Embedded Outpost'; managed = $null }
                )
            }

            @(Get-AuthentikSeededObject -Type Outposts).pk | Should-BeCollection @('o1')
            @(Get-AuthentikSeededObject -Type Certificates).pk | Should-BeCollection @('o1')
        }
    }

    It 'claims roles, policies, rules and transports by prefix, which is all they can carry' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @([PSCustomObject]@{ pk = 'a'; name = 'ZZ-TEST-Deny Contractors' }, [PSCustomObject]@{ pk = 'b'; name = 'Deny Everyone' })
            }

            @(Get-AuthentikSeededObject -Type Roles).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
            @(Get-AuthentikSeededObject -Type Policies).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
            @(Get-AuthentikSeededObject -Type NotificationRules).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
            @(Get-AuthentikSeededObject -Type NotificationTransports).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
        }
    }
}
