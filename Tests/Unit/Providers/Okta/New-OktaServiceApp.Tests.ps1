#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Registering the OAuth service app that replaces the bootstrap SSWS token.

    Most of this is ordinary seeding, but three behaviours are irreversible or close to it, and
    those are what most of the file is about:

    - Refusing to create a second app with the same label. Re-registering does not replace the
      first app, it produces a second, and the credential file for the old one stops working -
      so the private key of a still-existing app is gone.
    - Revoking the bootstrap API token ONLY after the new app has proven it can issue a token.
      Okta cannot restore a revoked token or recreate one with the same value, and rotating this
      app's key later needs an SSWS token, so revoking an unproven replacement leaves no way
      back except the admin console.
    - Saying out loud when the private key ended up unencrypted.

    A test that passes because a mock was never reached would hide exactly these, so the
    interlock tests assert on the revoke call not happening rather than on the warning text.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaServiceApp' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{
                    OrgUrl   = 'https://trial-1.okta.com'
                    Prefix   = 'OKTALAB'
                    AuthType = 'ApiToken'
                }
            }

            Mock Get-OktaCredentialPath { 'TestDrive:/okta-app.json' }
            Mock New-OktaRsaKeyPair {
                @{
                    PublicJwk  = @{ kty = 'RSA'; kid = 'kid-1'; n = 'nnn'; e = 'AQAB' }
                    PrivateJwk = @{ kty = 'RSA'; kid = 'kid-1'; d = 'ddd' }
                }
            }

            # Protected and encrypted by default, so the warning paths only fire where a test
            # deliberately puts them in a worse state.
            Mock Export-OktaAppCredential {
                @{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $true }
            }

            Mock Get-OktaAccessToken { @{ Scopes = @('okta.users.manage') } }
            Mock Write-TestMessage { }
            Mock Resolve-OktaApiToken { @{ id = 'tok1'; name = 'bootstrap' } }
            Mock Revoke-OktaApiToken { $true }

            # No app exists yet; registration returns a client id.
            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                if ($Path -eq '/oauth2/v1/clients') { return [PSCustomObject]@{ client_id = 'cid1' } }
                if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                    return [PSCustomObject]@{ id = 'app1' }
                }
                return $null
            }
        }
    }

    Context 'Core Functionality' {

        It 'registers a service app that authenticates with a key rather than a secret' {
            # private_key_jwt with an inline JWKS is what makes the app usable without storing
            # a shared secret anywhere. A client secret would defeat the point of the exercise.
            InModuleScope TestEnvironment {
                $r = New-OktaServiceApp -PassThru -Confirm:$false

                $r.ClientId | Should-Be 'cid1'
                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients' -and
                    $Body.token_endpoint_auth_method -eq 'private_key_jwt' -and
                    $Body.application_type -eq 'service' -and
                    $Body.grant_types -contains 'client_credentials' -and
                    @($Body.jwks.keys).Count -eq 1
                }
            }
        }

        It 'reads the app instance back rather than assuming the id matches the client id' {
            InModuleScope TestEnvironment {
                $r = New-OktaServiceApp -PassThru -Confirm:$false
                $r.AppId | Should-Be 'app1'
            }
        }

        It 'falls back to the client id when the app instance cannot be read' {
            InModuleScope TestEnvironment {
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') { throw 'HTTP 404' }
                    return $null
                }

                $r = New-OktaServiceApp -PassThru -Confirm:$false
                $r.AppId | Should-Be 'cid1'
            }
        }

        It 'grants every requested scope and assigns every requested role' {
            InModuleScope TestEnvironment {
                $r = New-OktaServiceApp -Scope okta.users.read, okta.groups.read `
                    -AdminRole READ_ONLY_ADMIN -PassThru -Confirm:$false

                @($r.Scopes) | Should-BeCollection @('okta.users.read', 'okta.groups.read')
                @($r.AdminRoles) | Should-BeCollection @('READ_ONLY_ADMIN')
                @($r.Warnings) | Should-BeCollection -Count 0
            }
        }

        It 'warns when connected as something other than an API token' {
            # The seeded app is deliberately not granted okta.clients.manage, so it cannot
            # register another app. Failing later with a bare 403 explains nothing.
            InModuleScope TestEnvironment {
                Mock Get-OktaConnection {
                    @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'; AuthType = 'ServiceApp' }
                }

                $null = New-OktaServiceApp -PassThru -Confirm:$false -WarningVariable warned `
                    -WarningAction SilentlyContinue

                @($warned) | Should-BeCollection -Count 1
                "$warned" | Should-MatchString 'okta\.clients\.manage'
            }
        }
    }

    Context 'Replacing An Existing App' -Tag 'Security' {

        It 'refuses to create a second app with the same label' {
            # Re-registering produces a second app rather than replacing the first, and the
            # credential file for the old one is overwritten - so its key is gone while the app
            # itself still exists and still has SUPER_ADMIN.
            InModuleScope TestEnvironment {
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') {
                        return @([PSCustomObject]@{
                            id = 'existing1'; label = 'OKTALAB Test Environment Automation' })
                    }
                    return $null
                }

                { New-OktaServiceApp -Confirm:$false } |
                    Should-Throw -ExceptionMessage '*already exists*'

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients'
                }
            }
        }

        It 'deactivates before deleting when replacing with -Force' {
            # Okta refuses to delete an active app, so a missing deactivate turns -Force into
            # a failure that leaves the old app in place.
            InModuleScope TestEnvironment {
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') {
                        return @([PSCustomObject]@{
                            id = 'existing1'; label = 'OKTALAB Test Environment Automation' })
                    }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    return $null
                }

                $null = New-OktaServiceApp -Force -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/apps/existing1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/apps/existing1'
                }
            }
        }
    }

    Context 'Credential Protection' -Tag 'Security' {

        It 'passes the vault through when asked for SecretStore' {
            InModuleScope TestEnvironment {
                # Mocked because the real one reaches the machine's SecretStore, which is per
                # user and shared with anything else that has ever used it. This test asks one
                # question - is -VaultName forwarded - and it was answering it only on machines
                # whose store happened to open with the module's default password. It began
                # failing the moment the Okta provider started using Core's vault helper, whose
                # default differs from the one this workstation's store was configured with,
                # which is a fact about the workstation rather than about the code under test.
                Mock Initialize-TestSecretVault {
                    [PSCustomObject]@{ VaultName = $VaultName; Available = $true; Created = $false }
                }
                Mock Export-OktaAppCredential {
                    @{ Protection = 'SecretStore'; VaultName = 'MyVault'; FileProtected = $true }
                }

                $r = New-OktaServiceApp -UseSecretStore -VaultName MyVault `
                    -PassThru -Confirm:$false

                $r.Protection | Should-Be 'SecretStore'
                Should-Invoke Export-OktaAppCredential -Times 1 -Exactly -ParameterFilter {
                    $UseSecretStore -and $VaultName -eq 'MyVault'
                }
            }
        }

        It 'says so when the private key ends up unencrypted' {
            # An unprotected key is a state the user can fix, but only if they are told they
            # are in it. Recording it only in the file would not reach anyone.
            InModuleScope TestEnvironment {
                Mock Export-OktaAppCredential {
                    @{ Protection = 'None'; VaultName = $null; FileProtected = $true }
                }

                $r = New-OktaServiceApp -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                @($r.Warnings | Where-Object { $_ -match 'UNENCRYPTED' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'says so when the file could not be locked down' {
            InModuleScope TestEnvironment {
                Mock Export-OktaAppCredential {
                    @{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $false }
                }

                $r = New-OktaServiceApp -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                @($r.Warnings | Where-Object { $_ -match 'could not be' }) |
                    Should-BeCollection -Count 1
            }
        }
    }

    Context 'API Token Revocation' -Tag 'Security' {

        It 'revokes the named token once the new app has issued one' {
            InModuleScope TestEnvironment {
                $r = New-OktaServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false

                $r.ApiTokenRevoked | Should-Be 'bootstrap'
                Should-Invoke Revoke-OktaApiToken -Times 1 -Exactly -ParameterFilter {
                    $TokenId -eq 'tok1'
                }
            }
        }

        It 'does not revoke when the new app could not issue a token' {
            # The interlock that matters most. Revocation is irreversible, and rotating this
            # app's key later needs an SSWS token - so throwing the bootstrap credential away
            # before its replacement works leaves no route back except the admin console.
            InModuleScope TestEnvironment {
                Mock Get-OktaAccessToken { throw 'HTTP 403 grant not yet propagated' }

                $r = New-OktaServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                Should-NotInvoke Revoke-OktaApiToken
                Should-NotInvoke Resolve-OktaApiToken
                $r.ApiTokenRevoked | Should-BeNull
                @($r.Warnings | Where-Object { $_ -match 'unproven' }) | Should-BeCollection -Count 1
            }
        }

        It 'revokes nothing when the token name cannot be resolved' {
            # An ambiguous or unknown name is refused rather than guessed at. An org routinely
            # holds several tokens, and guessing would eventually revoke somebody's CI.
            InModuleScope TestEnvironment {
                Mock Resolve-OktaApiToken { throw "More than one token matches 'bootstrap'" }

                $r = New-OktaServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                Should-NotInvoke Revoke-OktaApiToken
                $r.ApiTokenRevoked | Should-BeNull
                @($r.Warnings | Where-Object { $_ -match 'Could not revoke' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'leaves the token alone when no revocation was asked for' {
            InModuleScope TestEnvironment {
                $r = New-OktaServiceApp -PassThru -Confirm:$false

                Should-NotInvoke Revoke-OktaApiToken
                $r.ApiTokenRevoked | Should-BeNull
            }
        }
    }

    Context 'Error Handling' {

        It 'keeps going when a single scope grant fails, and reports which' {
            # A partially granted app is recoverable by hand; a failed run that created the app
            # anyway and said nothing is not.
            InModuleScope TestEnvironment {
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    if ($Path -like '*/grants' -and $Body.scopeId -eq 'okta.groups.read') {
                        throw 'HTTP 403 scope not available'
                    }
                    return $null
                }

                $r = New-OktaServiceApp -Scope okta.users.read, okta.groups.read `
                    -PassThru -Confirm:$false -WarningAction SilentlyContinue

                @($r.Scopes) | Should-BeCollection @('okta.users.read')
                @($r.Warnings | Where-Object { $_ -match 'okta\.groups\.read' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'explains the consequence when the admin role cannot be assigned' {
            # Scopes without a role produce an app that authenticates and then 403s on every
            # call, which is a confusing state to debug from the symptom.
            InModuleScope TestEnvironment {
                Mock Invoke-OktaRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    if ($Path -like '*/roles') { throw 'HTTP 403 requires super admin' }
                    return $null
                }

                $r = New-OktaServiceApp -PassThru -Confirm:$false -WarningAction SilentlyContinue

                @($r.AdminRoles) | Should-BeCollection -Count 0
                @($r.Warnings | Where-Object { $_ -match '403' }) | Should-BeCollection -Count 1
            }
        }
    }

    Context 'Safety' {

        It 'registers nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                $null = New-OktaServiceApp -WhatIf

                Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients'
                }
                Should-NotInvoke New-OktaRsaKeyPair
                Should-NotInvoke Export-OktaAppCredential
            }
        }

        It 'revokes nothing under -WhatIf, even when a token is named' {
            InModuleScope TestEnvironment {
                $null = New-OktaServiceApp -RevokeApiToken bootstrap -WhatIf

                Should-NotInvoke Revoke-OktaApiToken
            }
        }
    }
}
