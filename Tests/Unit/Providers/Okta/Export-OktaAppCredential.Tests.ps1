#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The service app credential file, end to end through Export-OktaAppCredential and
    Import-OktaAppCredential: no readable key material on disk by default, the protection method
    recorded as used, an exact round trip, a key that still signs afterwards, and the version 1
    file written before this module encrypted anything still read, with a warning, because
    refusing it would strand an environment seeded with an earlier build.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "okta-cred-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    # Inside InModuleScope, $script: resolves to the MODULE's scope rather than this file's, so
    # the path has to be pushed across explicitly. Reading $script:Scratch in there without this
    # silently yields $null, which surfaces as "cannot bind argument to parameter 'Path'".
    InModuleScope TestEnvironment -Parameters @{ ScratchPath = $script:Scratch } {
        param($ScratchPath)
        $script:Scratch = $ScratchPath
    }
}

AfterAll {
    Remove-Item -Path $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Credential file storage' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Jwk = [ordered]@{
                kty = 'RSA'; kid = 'test-kid'; alg = 'RS256'
                e = 'AQAB'; n = 'bW9kdWx1cw'; d = 'U0VDUkVUS0VZTUFURVJJQUw'
                p = 'cA'; q = 'cQ'; dp = 'ZHA'; dq = 'ZHE'; qi = 'cWk'
            }
        }
    }

    It 'writes no readable key material to disk by default' {
        # The whole point of the change. Anyone who can read the file must not be able to read
        # the key out of it.
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'default.json'
            $null = Export-OktaAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $raw = Get-Content -Path $path -Raw
            $raw.Contains('U0VDUkVUS0VZTUFURVJJQUw') | Should-BeFalse
            $raw.Contains('"d"') | Should-BeFalse
        }
    }

    It 'records the protection method it actually used' {
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'method.json'
            $result = Export-OktaAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $stored = Get-Content -Path $path -Raw | ConvertFrom-Json
            $stored.schemaVersion | Should-Be 2
            $stored.protection | Should-Be $result.Protection
        }
    }

    It 'round-trips the key through the file unchanged' {
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'roundtrip.json'
            $null = Export-OktaAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $read = Import-OktaAppCredential -Path $path

            $read.privateJwk.d | Should-Be 'U0VDUkVUS0VZTUFURVJJQUw'
            $read.privateJwk.kid | Should-Be 'test-kid'
            $read.clientId | Should-Be '0oaTEST'
            @($read.scopes) | Should-BeCollection @('okta.users.manage')
        }
    }

    It 'produces a key that can still sign an assertion after the round trip' {
        # The end-to-end property. Encryption that corrupts the key by a byte would pass every
        # test above and fail only against Okta, with a 401 that explains nothing.
        InModuleScope TestEnvironment {
            $keyPair = New-OktaRsaKeyPair -KeySize 2048
            $path = Join-Path $script:Scratch 'signing.json'

            $null = Export-OktaAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $keyPair.PrivateJwk -Confirm:$false

            $read = Import-OktaAppCredential -Path $path
            $assertion = New-OktaClientAssertion -PrivateJwk $read.privateJwk `
                -ClientId '0oaTEST' -Audience 'https://trial-1.okta.com/oauth2/v1/token'

            @($assertion -split '\.').Count | Should-Be 3
        }
    }

    It 'still reads a schema version 1 file, and says it should be replaced' {
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'legacy.json'
            $legacy = [ordered]@{
                schemaVersion = 1
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaLEGACY'
                appId         = '0oaLEGACY'
                label         = 'Lab'
                scopes        = @('okta.users.manage')
                privateJwk    = $script:Jwk
            }
            Set-Content -Path $path -Value ($legacy | ConvertTo-Json -Depth 10)

            $warnings = @()
            $read = Import-OktaAppCredential -Path $path -WarningVariable warnings `
                -WarningAction SilentlyContinue

            $read.privateJwk.d | Should-Be 'U0VDUkVUS0VZTUFURVJJQUw'
            $read.protection | Should-Be 'None'
            @($warnings).Count | Should-BeGreaterThan 0
        }
    }

    It 'refuses a file whose protection method and payload disagree' {
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'mismatch.json'
            Set-Content -Path $path -Value (@{
                schemaVersion = 2
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaX'
                appId         = '0oaX'
                protection    = 'DPAPI'
            } | ConvertTo-Json)

            { Import-OktaAppCredential -Path $path } | Should-Throw -ExceptionMessage '*no protected key*'
        }
    }

    It 'refuses a SecretStore pointer that names no vault' {
        InModuleScope TestEnvironment {
            $path = Join-Path $script:Scratch 'novault.json'
            Set-Content -Path $path -Value (@{
                schemaVersion = 2
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaX'
                appId         = '0oaX'
                protection    = 'SecretStore'
            } | ConvertTo-Json)

            { Import-OktaAppCredential -Path $path } |
                Should-Throw -ExceptionMessage '*does not name the vault*'
        }
    }

    It 'restricts the credential file to the current user' {
        InModuleScope TestEnvironment {
            if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
                $path = Join-Path $script:Scratch 'acl.json'
                $null = Export-OktaAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                    -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                    -PrivateJwk $script:Jwk -Confirm:$false

                $acl = Get-Acl -Path $path
                $acl.AreAccessRulesProtected | Should-BeTrue
                @($acl.Access).Count | Should-Be 1
            }
        }
    }
}
