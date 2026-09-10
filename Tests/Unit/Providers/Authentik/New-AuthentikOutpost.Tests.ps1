#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    An outpost is a record of where providers are served from, and the seed creates it with
    no service connection so nothing is ever deployed. What is pinned: the providers are
    resolved from the seeded applications, a provider of the wrong kind for the outpost is
    reported rather than sent, no service connection is ever set, and a re-run updates the
    outpost by name rather than creating a second.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikOutpost' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @(
                        [PSCustomObject]@{ slug = 'zz-test-intranet'; provider = 11; provider_obj = [PSCustomObject]@{ component = 'ak-provider-proxy-form'; name = 'ZZ-TEST-Intranet Portal Provider' } }
                        [PSCustomObject]@{ slug = 'zz-test-directory'; provider = 12; provider_obj = [PSCustomObject]@{ component = 'ak-provider-ldap-form'; name = 'ZZ-TEST-Directory Gateway Provider' } }
                        [PSCustomObject]@{ slug = 'zz-test-network'; provider = 13; provider_obj = [PSCustomObject]@{ component = 'ak-provider-radius-form'; name = 'ZZ-TEST-Network Access Provider' } }
                        [PSCustomObject]@{ slug = 'zz-test-expenses'; provider = 14; provider_obj = [PSCustomObject]@{ component = 'ak-provider-oauth2-form'; name = 'x' } }
                    )
                }
                @()
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/outposts/instances/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = "op-$($script:Created.Count)"; name = $Body.name }
                }
                return [PSCustomObject]@{ pk = 'op-existing'; name = $Body.name }
            }
        }
    }

    It 'creates every outpost with the prefix, its type and the providers of the applications it names' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikOutpost -PassThru -Confirm:$false

            $r.TotalOutposts | Should-Be 3
            $r.CreatedOutposts | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            @($script:Created | Where-Object { -not $_.name.StartsWith('ZZ-TEST-') }) | Should-BeCollection -Count 0
            ($script:Created | Where-Object { $_.type -eq 'ldap' }).providers | Should-BeCollection @(12)
            ($script:Created | Where-Object { $_.type -eq 'radius' }).providers | Should-BeCollection @(13)
            ($script:Created | Where-Object { $_.type -eq 'proxy' }).providers | Should-BeCollection @(11)
        }
    }

    It 'never sets a service connection, so nothing is deployed' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikOutpost -Confirm:$false
            @($script:Created | Where-Object { $_.ContainsKey('service_connection') }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.config.authentik_host -ne 'https://auth.example.com' }) | Should-BeCollection -Count 0
        }
    }

    It 'refuses to put a provider of the wrong kind on an outpost and says so' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @([PSCustomObject]@{ slug = 'zz-test-intranet'; provider = 14; provider_obj = [PSCustomObject]@{ component = 'ak-provider-oauth2-form'; name = 'x' } })
                }
                @()
            }

            $r = New-AuthentikOutpost -OutpostName 'Edge Proxy' -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedOutposts | Should-Be 1
            @($r.Errors).Count | Should-Be 1
            $script:Created[0].providers | Should-BeCollection -Count 0
        }
    }

    It 'updates an outpost that already exists rather than creating a second' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Outposts') { return @([PSCustomObject]@{ pk = 'op-existing'; name = 'ZZ-TEST-Edge Proxy' }) }
                if ($Type -eq 'Applications') { return @([PSCustomObject]@{ slug = 'zz-test-intranet'; provider = 11; provider_obj = [PSCustomObject]@{ component = 'ak-provider-proxy-form'; name = 'x' } }) }
                @()
            }

            $r = New-AuthentikOutpost -OutpostName 'Edge Proxy' -PassThru -Confirm:$false

            $r.UpdatedOutposts | Should-Be 1
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/outposts/instances/op-existing/' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikOutpost -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
