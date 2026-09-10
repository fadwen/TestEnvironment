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

    It 'claims policies, rules and transports by prefix, which is all they can carry' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                @([PSCustomObject]@{ pk = 'a'; name = 'ZZ-TEST-Deny Contractors' }, [PSCustomObject]@{ pk = 'b'; name = 'Deny Everyone' })
            }

            @(Get-AuthentikSeededObject -Type Policies).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
            @(Get-AuthentikSeededObject -Type NotificationRules).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
            @(Get-AuthentikSeededObject -Type NotificationTransports).name | Should-BeCollection @('ZZ-TEST-Deny Contractors')
        }
    }
}
