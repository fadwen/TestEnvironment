#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The instance's default mappings are found by managed identifier, which is stable across
    instances where the primary key is not. Pinned: the lookup returns pks in the order asked
    for, skips an identifier the instance lacks without failing, and reads each kind once per
    session.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AuthentikManagedMapping' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; Prefix = 'ZZ-TEST-' }
            Mock Invoke-AuthentikRequest {
                if ($Path -eq '/propertymappings/provider/scope/') {
                    return @(
                        [PSCustomObject]@{ pk = 'pk-openid'; managed = 'goauthentik.io/providers/oauth2/scope-openid'; scope_name = 'openid' }
                        [PSCustomObject]@{ pk = 'pk-email'; managed = 'goauthentik.io/providers/oauth2/scope-email'; scope_name = 'email' }
                        [PSCustomObject]@{ pk = 'pk-custom'; managed = $null; scope_name = 'custom' }
                    )
                }
                @([PSCustomObject]@{ pk = 'pk-upn'; managed = 'goauthentik.io/providers/saml/upn' })
            }
        }
    }

    It 'resolves managed identifiers to primary keys in the order asked for' {
        InModuleScope TestEnvironment {
            $pks = Get-AuthentikManagedMapping -Kind Scope -Managed 'goauthentik.io/providers/oauth2/scope-email', 'goauthentik.io/providers/oauth2/scope-openid' -Connection $script:Connection
            @($pks) | Should-BeCollection @('pk-email', 'pk-openid')
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/propertymappings/provider/scope/' -and $Query['managed__isnull'] -eq 'false' }
        }
    }

    It 'skips an identifier the instance lacks without failing' {
        InModuleScope TestEnvironment {
            $pks = Get-AuthentikManagedMapping -Kind Scope -Managed 'goauthentik.io/providers/oauth2/scope-openid', 'goauthentik.io/providers/oauth2/scope-profile' -Connection $script:Connection
            @($pks) | Should-BeCollection @('pk-openid')
        }
    }

    It 'reads each kind once per session' {
        InModuleScope TestEnvironment {
            $null = Get-AuthentikManagedMapping -Kind Scope -Managed 'goauthentik.io/providers/oauth2/scope-openid' -Connection $script:Connection
            $null = Get-AuthentikManagedMapping -Kind Scope -Managed 'goauthentik.io/providers/oauth2/scope-email' -Connection $script:Connection
            $null = Get-AuthentikManagedMapping -Kind Saml -Managed 'goauthentik.io/providers/saml/upn' -Connection $script:Connection
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/propertymappings/provider/scope/' }
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/propertymappings/provider/saml/' }
        }
    }
}
