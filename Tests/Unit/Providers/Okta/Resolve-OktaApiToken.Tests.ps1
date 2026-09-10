#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Revoking an Okta API token is permanent. There is no restore, and no way to recreate a token
    with the same value - a replacement is a new token made by hand in the admin console. So the
    resolve step has exactly two acceptable outcomes: one match, or an error.

    The danger is concrete rather than theoretical. The tenant this module was developed against
    held two tokens, one for this work and one named "postman testing". Anything that picked the
    first match, or matched on a prefix, would eventually revoke somebody's working credential.

    The design constraint behind all of it: the module cannot identify the token it is itself
    using. /api/v1/api-tokens/current returns 404 on a standard org, and the list endpoint
    returns ids and names but never token values, so an SSWS string cannot be matched to a row.
    That is why the caller has to name one.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-OktaApiToken' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                @(
                    [PSCustomObject]@{ id = '00T4cxwlhd2fCSwol697'; name = 'claude' }
                    [PSCustomObject]@{ id = '00T4cjt31qn3RQ0tr697'; name = 'postman testing' }
                    [PSCustomObject]@{ id = '00T4dupe1'; name = 'duplicate' }
                    [PSCustomObject]@{ id = '00T4dupe2'; name = 'duplicate' }
                )
            }
        }
    }

    It 'resolves an exact name' {
        InModuleScope TestEnvironment {
            (Resolve-OktaApiToken -NameOrId 'claude').id | Should-Be '00T4cxwlhd2fCSwol697'
        }
    }

    It 'resolves an exact id' {
        InModuleScope TestEnvironment {
            (Resolve-OktaApiToken -NameOrId '00T4cjt31qn3RQ0tr697').name | Should-Be 'postman testing'
        }
    }

    It 'matches a name case-insensitively' {
        InModuleScope TestEnvironment {
            (Resolve-OktaApiToken -NameOrId 'CLAUDE').id | Should-Be '00T4cxwlhd2fCSwol697'
        }
    }

    It 'refuses a name that matches more than one token' {
        # Never "pick the first". Two tokens can share a name, and the wrong one is unrecoverable.
        InModuleScope TestEnvironment {
            { Resolve-OktaApiToken -NameOrId 'duplicate' } | Should-Throw -ExceptionMessage '*matches 2*'
        }
    }

    It 'refuses a name that matches nothing, and says what does exist' {
        InModuleScope TestEnvironment {
            { Resolve-OktaApiToken -NameOrId 'nosuchtoken' } |
                Should-Throw -ExceptionMessage '*postman testing*'
        }
    }

    It 'does not match on a prefix' {
        # 'claud' must not resolve to 'claude'. A near miss here deletes a credential.
        InModuleScope TestEnvironment {
            { Resolve-OktaApiToken -NameOrId 'claud' } | Should-Throw
        }
    }

    It 'does not treat a wildcard as a wildcard' {
        InModuleScope TestEnvironment {
            { Resolve-OktaApiToken -NameOrId '*' } | Should-Throw
        }
    }

    It 'reports plainly when the org has no tokens at all' {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest { @() }
            { Resolve-OktaApiToken -NameOrId 'anything' } | Should-Throw -ExceptionMessage '*no API tokens*'
        }
    }
}

Describe 'Revoke-OktaApiToken' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest { $null }
        }
    }

    It 'deletes the token it was given' {
        InModuleScope TestEnvironment {
            $revoked = Revoke-OktaApiToken -TokenId '00T4abc' -TokenName 'bootstrap' -Confirm:$false

            $revoked | Should-BeTrue
            Should-Invoke Invoke-OktaRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Path -eq '/api/v1/api-tokens/00T4abc'
            }
        }
    }

    It 'revokes nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $revoked = Revoke-OktaApiToken -TokenId '00T4abc' -TokenName 'bootstrap' -WhatIf

            $revoked | Should-BeFalse
            Should-NotInvoke Invoke-OktaRequest
        }
    }
}

Describe 'New-OktaServiceApp revoke interlock' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{
                    OrgUrl              = 'https://trial-1.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                }
            }
            Mock Write-TestMessage { }
            Mock New-OktaRsaKeyPair {
                [PSCustomObject]@{
                    KeyId = 'k'; KeySize = 2048
                    PublicJwk = @{ kid = 'k' }; PrivateJwk = @{ kid = 'k' }
                }
            }
            Mock Export-OktaAppCredential {
                [PSCustomObject]@{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $true }
            }
            Mock Get-OktaCredentialPath { 'C:\temp\fake.serviceapp.json' }
            Mock Resolve-OktaApiToken { [PSCustomObject]@{ id = '00T4abc'; name = 'bootstrap' } }
            Mock Revoke-OktaApiToken { $true }

            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/oauth2/v1/clients') {
                    return [PSCustomObject]@{ client_id = '0oaNEW' }
                }
                if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                    return [PSCustomObject]@{ id = '0oaNEW' }
                }
                return $null
            }
        }
    }

    It 'revokes the named token once the app has proven itself' {
        InModuleScope TestEnvironment {
            Mock Get-OktaAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }

            $r = New-OktaServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false

            $r.ApiTokenRevoked | Should-Be 'bootstrap'
            Should-Invoke Revoke-OktaApiToken -Times 1 -Exactly
        }
    }

    It 'refuses to revoke when the new app cannot issue a token' {
        # The interlock that matters most. Rotating this app's key later needs an SSWS token,
        # so discarding the bootstrap credential before the replacement works would leave no
        # way back except the admin console.
        InModuleScope TestEnvironment {
            Mock Get-OktaAccessToken { throw 'invalid_client' }

            $r = New-OktaServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            $r.ApiTokenRevoked | Should-BeNull
            Should-NotInvoke Revoke-OktaApiToken
        }
    }

    It 'says why it declined to revoke' {
        InModuleScope TestEnvironment {
            Mock Get-OktaAccessToken { throw 'invalid_client' }

            $r = New-OktaServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            (@($r.Warnings) -join ' ') | Should-MatchString 'Not revoking'
        }
    }

    It 'revokes nothing when no token is named' {
        InModuleScope TestEnvironment {
            Mock Get-OktaAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }

            $null = New-OktaServiceApp -PassThru -Confirm:$false

            Should-NotInvoke Resolve-OktaApiToken
            Should-NotInvoke Revoke-OktaApiToken
        }
    }

    It 'carries on when the token cannot be resolved, rather than failing the app creation' {
        # The app exists and works at this point. An unresolvable token name is a reason to warn,
        # not to make the caller think the whole operation failed.
        InModuleScope TestEnvironment {
            Mock Get-OktaAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }
            Mock Resolve-OktaApiToken { throw "matches 2 API tokens" }

            $r = New-OktaServiceApp -RevokeApiToken 'duplicate' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            $r.ClientId | Should-Be '0oaNEW'
            $r.ApiTokenRevoked | Should-BeNull
            (@($r.Warnings) -join ' ') | Should-MatchString 'Could not revoke'
        }
    }
}
