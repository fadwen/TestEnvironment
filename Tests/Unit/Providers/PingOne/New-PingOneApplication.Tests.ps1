#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Application seeding. Two properties are pinned:

    - A public client (no secret) is never created without PKCE. That is not a test condition,
      it is the only safe way to run one, and seeding an unsafe public client would be seeding a
      live weakness rather than inert data.
    - A SAML application is granted no resource scopes, because it is issued no access tokens.

    Every call is mocked. This suite must never reach an environment.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-PingOneApplication' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-PingOneConnection {
                @{ EnvironmentId = '00000000-0000-4000-8000-000000000001'; Prefix = 'ZZ-TEST-'; EmailDomain = 'pingonelab.example.com' }
            }

            # Backstop: any call no test mocked fails loudly rather than reaching PingOne.
            Mock Invoke-PingOneRequest { throw "Escaped the mocks: $Method $Path" }
            # Every group and resource the data names exists, so failures here are about the
            # application itself and not about a missing dependency.
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'groups' } {
                foreach ($name in 'All Staff', 'Finance', 'Partners', 'Sales') {
                    [PSCustomObject]@{ id = "g-$name"; name = "ZZ-TEST-$name" }
                }
            }
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'resources' } {
                [PSCustomObject]@{ id = 'r-orders'; name = 'ZZ-TEST-Orders API' }
                [PSCustomObject]@{ id = 'r-reports'; name = 'ZZ-TEST-Reports API' }
            }
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' -and $Path -like 'resources/*/scopes' } {
                foreach ($scope in 'orders.read', 'orders.write', 'orders.admin', 'reports.read') {
                    [PSCustomObject]@{ id = "s-$scope"; name = $scope }
                }
            }
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' -and ($Path -eq 'applications' -or $Path -like 'applications/*/grants') } { }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            $script:Grants = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq 'applications' } {
                $script:Created.Add($Body)
                [PSCustomObject]@{ id = "app-$($Body.name)" }
            }
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' -and $Path -like 'applications/*/grants' } {
                $script:Grants.Add($Path)
            }
        }
    }

    It 'requires PKCE on every public client' {
        InModuleScope TestEnvironment {
            $null = New-PingOneApplication -Confirm:$false
            $public = @($script:Created | Where-Object { $_.tokenEndpointAuthMethod -eq 'NONE' })
            $public.Count | Should-BeGreaterThan 0
            @($public | Where-Object { $_.pkceEnforcement -ne 'S256_REQUIRED' }) | Should-BeCollection -Count 0
        }
    }

    It 'has no parameter that could create a public client without PKCE' {
        # A safety property with no switch, like a seeded population never being the default.
        InModuleScope TestEnvironment {
            $parameters = @((Get-Command New-PingOneApplication).Parameters.Keys)
            @($parameters | Where-Object { $_ -match 'Pkce' }) | Should-BeCollection -Count 0
        }
    }

    It 'grants no resource scopes to a SAML application' {
        InModuleScope TestEnvironment {
            $null = New-PingOneApplication -Key wiki-saml -Confirm:$false
            $script:Created.Count | Should-Be 1
            $script:Created[0].protocol | Should-Be 'SAML'
            $script:Grants | Should-BeCollection -Count 0
        }
    }

    It 'restricts access to groups through access control' {
        InModuleScope TestEnvironment {
            $null = New-PingOneApplication -Key payroll -Confirm:$false
            $script:Created[0].accessControl.group.groups.id | Should-BeCollection @('g-Finance')
        }
    }

    It 'writes redirect URLs against the connection domain, never a real host' {
        InModuleScope TestEnvironment {
            $null = New-PingOneApplication -Confirm:$false
            $urls = @($script:Created | ForEach-Object { $_.redirectUris; $_.acsUrls } | Where-Object { $_ -like 'http*' })
            $urls.Count | Should-BeGreaterThan 0
            @($urls | Where-Object { $_ -notlike '*pingonelab.example.com*' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-PingOneApplication -WhatIf
            Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
