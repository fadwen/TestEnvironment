#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The judgement that decides, before any prompt, which teardown layers an identity can
    remove. Two properties matter more than the table of permissions: an identity whose
    rights cannot be read must be allowed everything, because refusing on no evidence is the
    worse failure; and a service principal that is a Global Administrator must be allowed
    everything even though its token's roles claim says it can only read, which the README
    documents as the reason a claims-only check is a mistake.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-EntraTeardownCapability' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            # A fake JWT: header.payload.signature, with only the payload meaningful.
            $script:Jwt = {
                param($claims)
                $payload = ConvertTo-TestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
                'eyJhbGciOiJub25lIn0.' + $payload + '.sig'
            }
            $script:Connection = @{
                TenantId = 't'; ClientId = 'app-client'; AuthMode = 'Certificate'; GraphBaseUri = 'https://graph.microsoft.com'
                AccessToken = 'test-token'
            }
            # Graph answers nothing unless a test says otherwise: no principal, no roles.
            Mock Invoke-EntraRequest { @() }
        }
    }

    It 'allows every layer when the token is not a JWT and Graph reveals no roles' {
        InModuleScope TestEnvironment {
            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.Known | Should-BeFalse
            @($c.Layers.Values | Where-Object { -not $_.Allowed }) | Should-BeCollection -Count 0
        }
    }

    It 'refuses the policy layers to a delegated token that lacks the policy scopes, and allows the user layer it has' {
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ scp = 'User.ReadWrite.All Group.ReadWrite.All openid'; oid = 'u1' }
            $script:Connection.AuthMode = 'DeviceCode'

            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.Known | Should-BeTrue
            $c.IdentityKind | Should-Be 'User'
            $c.Layers['ConditionalAccessPolicies'].Allowed | Should-BeFalse
            $c.Layers['AuthenticationStrengths'].Allowed | Should-BeFalse
            $c.Layers['ConditionalAccessPolicies'].Reason | Should-MatchString 'Policy.ReadWrite.ConditionalAccess'
            $c.Layers['Users'].Allowed | Should-BeTrue
            $c.Layers['Groups'].Allowed | Should-BeTrue
        }
    }

    It 'reads an app-only token from its roles claim' {
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ roles = @('Policy.ReadWrite.ConditionalAccess', 'Directory.Read.All') }

            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.IdentityKind | Should-Be 'Application'
            $c.Layers['NamedLocations'].Allowed | Should-BeTrue
            $c.Layers['Users'].Allowed | Should-BeFalse
        }
    }

    It 'marks applications as owned-only under Application.ReadWrite.OwnedBy without the broader grant' {
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ roles = @('Application.ReadWrite.OwnedBy') }

            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.Layers['Applications'].Allowed | Should-BeTrue
            $c.ApplicationsOwnedOnly | Should-BeTrue

            $script:Connection.AccessToken = & $script:Jwt @{ roles = @('Application.ReadWrite.OwnedBy', 'Application.ReadWrite.All') }
            (Get-EntraTeardownCapability -Connection $script:Connection).ApplicationsOwnedOnly | Should-BeFalse
        }
    }

    It 'allows everything to a read-only-looking service principal that is a Global Administrator' {
        # The README case: the token says *.Read.All, the directory says Global Administrator,
        # and the directory is right. The roles come from Graph, not from the token.
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ roles = @('Directory.Read.All', 'Policy.Read.All') }
            Mock Invoke-EntraRequest {
                if ($Path -eq '/servicePrincipals') { return @([PSCustomObject]@{ id = 'sp-1' }) }
                if ($Path -like '/servicePrincipals/sp-1/transitiveMemberOf/*') {
                    return @([PSCustomObject]@{ roleTemplateId = '62e90394-69f5-4237-9190-012177145e10'; displayName = 'Global Administrator' })
                }
                @()
            }

            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.IdentityObjectId | Should-Be 'sp-1'
            $c.DirectoryRoles | Should-ContainCollection @('62e90394-69f5-4237-9190-012177145e10')
            @($c.Layers.Values | Where-Object { -not $_.Allowed }) | Should-BeCollection -Count 0
            $c.Layers['Users'].Reason | Should-MatchString 'directory role'
        }
    }

    It 'honours a directory role carried in the token when Graph cannot be read' {
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ scp = 'openid'; wids = @('9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3') }
            $script:Connection.AuthMode = 'DeviceCode'
            Mock Invoke-EntraRequest { throw 'Graph GET /me failed with HTTP 403' }

            $c = Get-EntraTeardownCapability -Connection $script:Connection

            $c.Layers['Applications'].Allowed | Should-BeTrue
            $c.Layers['Users'].Allowed | Should-BeFalse
        }
    }

    It 'resolves a user identity through /me' {
        InModuleScope TestEnvironment {
            $script:Connection.AccessToken = & $script:Jwt @{ scp = 'User.ReadWrite.All' }
            $script:Connection.AuthMode = 'DeviceCode'
            Mock Invoke-EntraRequest {
                if ($Path -eq '/me') { return [PSCustomObject]@{ id = 'user-9' } }
                @()
            }

            (Get-EntraTeardownCapability -Connection $script:Connection).IdentityObjectId | Should-Be 'user-9'
        }
    }
}
