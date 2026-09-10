#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    An invitation is the one object this module creates that can leave the tenant: it names an
    email address, and Entra will mail it. So the first Context here is about mail, and it is
    the same shape as the Conditional Access state tests - the safety property is that it is not
    configurable, not that the default happens to be right.

    The second Context pins the shape the four rows exist to produce. If a later edit made
    userType agree with the #EXT# marker on every row, the data would still look reasonable and
    would have stopped breaking the scripts it is for.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraGuestUser' -Tag 'Unit', 'Safety' {

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

            $script:SentRequests = [System.Collections.Generic.List[object]]::new()

            Mock Get-EntraSeededObject { @() }
            Mock Get-EntraSeededObject {
                @([PSCustomObject]@{ id = 'au-users'; displayName = 'ENTRALAB-Users' })
            } -ParameterFilter { $Type -eq 'AdministrativeUnits' }

            Mock Resolve-EntraSeededId { "group-$Key" }
            Mock Add-EntraUnitMember { 0 }
            Mock Invoke-EntraBatch { @() }
            Mock New-TestPassword { 'not-a-real-password' }

            Mock Invoke-EntraRequest {
                $script:SentRequests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })

                # Nothing exists yet. The GET is the idempotence probe, and the invited branch
                # reads an empty collection while the direct branch expects a 404.
                if ($Method -eq 'GET') {
                    if ($Path -like '/users/*') { throw 'Request_ResourceNotFound' }
                    return @()
                }
                if ($Path -eq '/invitations') {
                    return [PSCustomObject]@{ invitedUser = [PSCustomObject]@{ id = "guest-$($script:SentRequests.Count)" } }
                }
                return [PSCustomObject]@{ id = "user-$($script:SentRequests.Count)" }
            }
        }
    }

    Context 'Nothing ever leaves the tenant' {

        It 'never asks Entra to send an invitation message' {
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                $invitations = @($script:SentRequests | Where-Object { $_.Path -eq '/invitations' })
                $invitations.Count | Should-BeGreaterThan 0

                foreach ($invitation in $invitations) {
                    $invitation.Body.sendInvitationMessage | Should-BeFalse
                }
            }
        }

        It 'exposes no parameter that could make it send mail' {
            $command = Get-Command New-EntraGuestUser
            $command.Parameters.Keys | Should-NotContainCollection @('SendInvitationMessage')
            $command.Parameters.Keys | Should-NotContainCollection @('SendMail')
            $command.Parameters.Keys | Should-NotContainCollection @('Notify')
        }

        It 'invites only addresses nobody can receive' {
            # Asserted on what is actually sent rather than on the CSV, because the address is
            # built at run time by substituting the prefix and a template bug could put a real
            # domain on the wire while the data still reads correctly.
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                foreach ($invitation in @($script:SentRequests | Where-Object { $_.Path -eq '/invitations' })) {
                    $domain = ($invitation.Body.invitedUserEmailAddress -split '@')[-1]
                    @('example.com', 'example.net', 'example.org') | Should-ContainCollection @($domain)
                }
            }
        }

        It 'redirects redemption to a reserved domain too' {
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                foreach ($invitation in @($script:SentRequests | Where-Object { $_.Path -eq '/invitations' })) {
                    $invitation.Body.inviteRedirectUrl | Should-MatchString '^https://example\.com/'
                }
            }
        }
    }

    Context 'The shape the rows exist to produce' {

        It 'carries the seed prefix into every invited address' {
            # What keeps a B2B guest findable at teardown. Entra mints the UPN from this
            # address, so the prefix survives into it only from the local part.
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                foreach ($invitation in @($script:SentRequests | Where-Object { $_.Path -eq '/invitations' })) {
                    $invitation.Body.invitedUserEmailAddress | Should-MatchString '^ENTRALAB-'
                }
            }
        }

        It 'invites one external identity as a member rather than a guest' {
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                $invitations = @($script:SentRequests | Where-Object { $_.Path -eq '/invitations' })
                @($invitations | Where-Object { $_.Body.invitedUserType -eq 'Member' }).Count |
                    Should-BeGreaterThan 0
                @($invitations | Where-Object { $_.Body.invitedUserType -eq 'Guest' }).Count |
                    Should-BeGreaterThan 0
            }
        }

        It 'creates one guest locally, so userType and the UPN disagree in both directions' {
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                $direct = @($script:SentRequests |
                        Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/users' })

                $direct.Count | Should-BeGreaterThan 0
                foreach ($post in $direct) {
                    $post.Body.userType | Should-Be 'Guest'

                    # An ordinary in-tenant UPN. This is the row that has no #EXT# in it, which
                    # is the whole reason it is created through a different endpoint.
                    $post.Body.userPrincipalName | Should-MatchString '@contoso\.onmicrosoft\.com$'
                }
            }
        }

        It 'tags every identity it creates, whichever endpoint made it' {
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                $patches = @($script:SentRequests | Where-Object { $_.Method -eq 'PATCH' })
                $patches.Count | Should-BeGreaterThan 0

                foreach ($patch in $patches) {
                    $patch.Body.onPremisesExtensionAttributes.extensionAttribute15 |
                        Should-MatchString '\S'
                }
            }
        }

        It 'leaves at least one external identity with no usageLocation' {
            # The default state of every invitation, and the state in which licence assignment
            # fails. Sending a usageLocation on all four would quietly remove that case.
            InModuleScope TestEnvironment {
                New-EntraGuestUser | Out-Null

                $patches = @($script:SentRequests | Where-Object { $_.Method -eq 'PATCH' })
                @($patches | Where-Object { -not $_.Body.ContainsKey('usageLocation') }).Count |
                    Should-BeGreaterThan 0
            }
        }
    }
}
