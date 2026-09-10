#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Attaching a scope mapping to a provider is a PATCH of the provider's whole mapping list,
    and the list it was created with holds the standard OpenID scopes. Replace rather than
    merge and every token from that provider loses its email and profile claims, which is a
    failure nothing in the seed would notice. The merge is pinned, along with the skip for a
    provider that is not OAuth2 and the promise not to re-attach what is already there.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikScopeMapping' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @(
                        [PSCustomObject]@{ slug = 'zz-test-expenses'; provider = 21 }
                        [PSCustomObject]@{ slug = 'zz-test-payroll'; provider = 22 }
                        [PSCustomObject]@{ slug = 'zz-test-intranet'; provider = 23 }
                    )
                }
                @()
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            $script:ProviderPatches = @{}
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/propertymappings/provider/scope/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = "map-$($script:Created.Count)"; name = $Body.name }
                }
                if ($Method -eq 'GET' -and $Path -like '/providers/oauth2/2[12]/') {
                    return [PSCustomObject]@{ pk = 21; property_mappings = @('std-openid', 'std-email') }
                }
                if ($Method -eq 'GET' -and $Path -eq '/providers/oauth2/23/') { throw 'Authentik GET failed with HTTP 404: not found' }
                if ($Method -eq 'PATCH') { $script:ProviderPatches[$Path] = $Body; return $null }
                return $null
            }
        }
    }

    It 'creates every mapping with the prefix and the scope name as written' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikScopeMapping -PassThru -Confirm:$false

            $r.TotalMappings | Should-Be 3
            $r.CreatedMappings | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            $script:Created[0].name | Should-Be 'ZZ-TEST-Lab Profile'
            $script:Created[0].scope_name | Should-Be 'lab_profile'
            $script:Created[0].expression | Should-MatchString 'labClearanceLevel'
        }
    }

    It 'attaches to the provider by merging with the mappings it already carries' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikScopeMapping -MappingName Lab-Profile -PassThru -Confirm:$false

            $r.ProvidersUpdated | Should-Be 2
            @($script:ProviderPatches['/providers/oauth2/21/'].property_mappings) | Should-BeCollection @('std-openid', 'std-email', 'map-1')
            @($script:ProviderPatches['/providers/oauth2/22/'].property_mappings) | Should-BeCollection @('std-openid', 'std-email', 'map-1')
        }
    }

    It 'does not re-attach a mapping the provider already has' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST') { return [PSCustomObject]@{ pk = 'map-1' } }
                if ($Method -eq 'GET') { return [PSCustomObject]@{ property_mappings = @('std-openid', 'map-1') } }
                if ($Method -eq 'PATCH') { $script:ProviderPatches[$Path] = $Body }
                return $null
            }

            $r = New-AuthentikScopeMapping -MappingName Lab-Entitlements -PassThru -Confirm:$false

            $r.ProvidersUpdated | Should-Be 0
            $script:ProviderPatches.Count | Should-Be 0
            $r.Mappings[0].Applications | Should-BeCollection @('zz-test-expenses')
        }
    }

    It 'skips a provider that is not OAuth2 and says so' {
        InModuleScope TestEnvironment {
            # A mapping row that names the proxy-fronted intranet does not exist in the CSV, so
            # the case is exercised by pointing the expenses application at the proxy provider.
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') { return @([PSCustomObject]@{ slug = 'zz-test-expenses'; provider = 23 }) }
                @()
            }

            $r = New-AuthentikScopeMapping -MappingName Lab-Entitlements -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedMappings | Should-Be 1
            $r.ProvidersUpdated | Should-Be 0
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'not OAuth2'
        }
    }

    It 'attaches nothing under -SkipProvider' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikScopeMapping -SkipProvider -Confirm:$false
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'PATCH' -or $Path -like '/providers/*' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikScopeMapping -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
