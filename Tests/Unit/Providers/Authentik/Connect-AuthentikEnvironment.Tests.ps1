#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Connecting is the one step every other command depends on, and its two failure modes are
    both quiet: a connection stored before it was proven leaves every later command failing
    with an unrelated message, and a -PassThru that carried the bearer token would put it in
    every transcript. Both are pinned here, along with the service-account route reading the
    record rather than asking for a token.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test tokens, typed into a test file.')]
param()

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-AuthentikEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:AuthentikConnection = $null
            $script:Token = ConvertTo-SecureString -String 'ak-token' -AsPlainText -Force
            Mock Invoke-AuthentikRequest {
                [PSCustomObject]@{ user = [PSCustomObject]@{ username = 'akadmin'; pk = 1 } }
            }
        }
    }

    It 'proves the token against the current-user endpoint before storing anything' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest { throw 'Authentik GET /core/users/me/ failed with HTTP 403: Invalid token.' }

            { Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ApiToken $script:Token } |
                Should-Throw -ExceptionMessage '*Could not authenticate*'

            $script:AuthentikConnection | Should-BeNull
        }
    }

    It 'stores the connection with the identity the token belongs to' {
        InModuleScope TestEnvironment {
            Connect-AuthentikEnvironment -BaseUrl 'https://auth.example.com/' -ApiToken $script:Token

            $script:AuthentikConnection.BaseUrl | Should-Be 'https://auth.example.com'
            $script:AuthentikConnection.AuthorizationHeader | Should-Be 'Bearer ak-token'
            $script:AuthentikConnection.Identity | Should-Be 'akadmin'
            $script:AuthentikConnection.AuthType | Should-Be 'ApiToken'
            $script:AuthentikConnection.Prefix | Should-Be 'ZZ-TEST-'
            $script:AuthentikConnection.SeedTag | Should-Be 'ZZ-TEST-seed'
        }
    }

    It 'never returns the Authorization header' {
        InModuleScope TestEnvironment {
            $result = Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ApiToken $script:Token -PassThru

            $result.PSObject.Properties.Name | Should-NotContainCollection @('AuthorizationHeader')
            ($result | ConvertTo-Json -Depth 3) | Should-NotMatchString 'ak-token'
            $result.Identity | Should-Be 'akadmin'
        }
    }

    It 'rejects a prefix with no trailing separator' {
        InModuleScope TestEnvironment {
            { Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ApiToken $script:Token -Prefix 'LAB' } | Should-Throw
        }
    }

    It 'reads the record rather than asking for a token under -ServiceAccount' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikCredentialPath { 'C:\record.json' }
            Mock Import-AuthentikCredential {
                [PSCustomObject]@{ BaseUrl = 'https://auth.example.com'; Username = 'zz-test-automation'; UserPk = 9; Token = 'svc-token'; Protection = 'DPAPI' }
            }
            Mock Invoke-AuthentikRequest { [PSCustomObject]@{ user = [PSCustomObject]@{ username = 'zz-test-automation' } } }

            Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ServiceAccount

            $script:AuthentikConnection.AuthType | Should-Be 'ServiceAccount'
            $script:AuthentikConnection.AuthorizationHeader | Should-Be 'Bearer svc-token'
            $script:AuthentikConnection.CredentialPath | Should-Be 'C:\record.json'
            Should-Invoke Import-AuthentikCredential -Times 1 -Exactly
        }
    }

    It 'clears the connection on disconnect' {
        InModuleScope TestEnvironment {
            Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ApiToken $script:Token
            $result = Disconnect-AuthentikEnvironment -Confirm:$false -PassThru

            $script:AuthentikConnection | Should-BeNull
            $result.BaseUrl | Should-Be 'https://auth.example.com'
        }
    }
}
