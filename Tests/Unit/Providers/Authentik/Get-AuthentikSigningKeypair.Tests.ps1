#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The SAML provider signs with a keypair the seed owns, never one the instance already has.
    Pinned: an existing seeded keypair is reused, an unseeded one with a different name is
    never picked up, and the generate call asks Authentik to make the key so the private half
    never passes through the module.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}


Describe 'Get-AuthentikSigningKeypair' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
        }
    }

    It 'generates a self-signed keypair with the prefixed name when none exists' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }
            Mock Invoke-AuthentikRequest { [PSCustomObject]@{ pk = 'kp-new'; name = $Body.common_name } }

            Get-AuthentikSigningKeypair | Should-Be 'kp-new'

            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/crypto/certificatekeypairs/generate/' -and
                $Body.common_name -eq 'ZZ-TEST-SAML Signing' -and $Body.validity_days -gt 0
            }
        }
    }

    It 'reuses the seeded keypair and generates nothing' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                @(
                    [PSCustomObject]@{ pk = 'kp-other'; name = 'ZZ-TEST-Something Else' }
                    [PSCustomObject]@{ pk = 'kp-ours'; name = 'ZZ-TEST-SAML Signing' }
                )
            }
            Mock Invoke-AuthentikRequest { throw 'must not be called' }

            Get-AuthentikSigningKeypair | Should-Be 'kp-ours'
            Should-NotInvoke Invoke-AuthentikRequest
        }
    }
}
