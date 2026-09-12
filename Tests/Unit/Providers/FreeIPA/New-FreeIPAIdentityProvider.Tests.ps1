#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A RADIUS proxy and an identity provider are where a user's authentication is sent, and
    each carries a secret. What is pinned: the proxy pointed at a seeded host by its real
    name with the marker in its description, the provider created from FreeIPA's template
    for its kind with the seed's client, a fresh random secret sent once on creation and
    never on a re-run, never kept and never returned; and no request that names anything
    without the prefix.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAIdentityProvider' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates each proxy at a seeded host with the marker, and each provider from its template with the seed client, with a random secret sent once' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAIdentityProvider -PassThru -Confirm:$false
            $r.TotalProviders | Should-Be 4
            $r.CreatedProxies | Should-Be 2
            $r.CreatedIdps | Should-Be 2
            $r.Errors | Should-BeCollection -Count 0

            $legacy = ($script:Calls | Where-Object { $_.Method -eq 'radiusproxy_add' -and $_.Arguments[0] -eq 'zz-test-legacy-radius' }).Options
            $legacy.ipatokenradiusserver | Should-Be 'zz-test-legacy01.zz-test-lab.ipa.example.com:1812'
            $legacy.description | Should-MatchString '\[ZZ-TEST-seed\]$'
            $legacy.ipatokenradiustimeout | Should-Be 5
            $legacy.ipatokenradiusretries | Should-Be 2
            $legacy.ipatokenusermapattribute | Should-Be 'uid'
            $legacy.ipatokenradiussecret | Should-MatchString '^.{32}$'
            $dead = ($script:Calls | Where-Object { $_.Method -eq 'radiusproxy_add' -and $_.Arguments[0] -eq 'zz-test-decommissioned-radius' }).Options
            $dead.ipatokenradiusserver | Should-Be 'radius.decommissioned.example.invalid:1812'
            # Two proxies, two different secrets.
            $legacy.ipatokenradiussecret | Should-NotBe $dead.ipatokenradiussecret

            $github = ($script:Calls | Where-Object { $_.Method -eq 'idp_add' -and $_.Arguments[0] -eq 'zz-test-github' }).Options
            $github.ipaidpprovider | Should-Be 'github'
            $github.ipaidpclientid | Should-Be 'zz-test-lab-client'
            $github.ipaidpscope | Should-Be 'user:email'
            $github.ipaidpsub | Should-Be 'login'
            $github.ipaidpclientsecret | Should-MatchString '^.{32}$'
            $github.ContainsKey('ipaidporg') | Should-BeFalse
            $keycloak = ($script:Calls | Where-Object { $_.Method -eq 'idp_add' -and $_.Arguments[0] -eq 'zz-test-keycloak-pilot' }).Options
            $keycloak.ipaidpprovider | Should-Be 'keycloak'
            $keycloak.ipaidporg | Should-Be 'lab'
            $keycloak.ipaidpbaseurl | Should-Be 'sso.zz-test-lab.ipa.example.com'

            # Never returned.
            ($r | ConvertTo-Json -Depth 5) | Should-NotMatchString ([regex]::Escape($legacy.ipatokenradiussecret))
            ($r | ConvertTo-Json -Depth 5) | Should-NotMatchString ([regex]::Escape($github.ipaidpclientsecret))
            @($r.Providers | Get-Member -MemberType NoteProperty).Name | Should-NotContainCollection @('Secret', 'ClientSecret')
        }
    }

    It 'modifies what exists without sending a secret or a template, and names nothing without the prefix' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject {
                if ($Type -eq 'RadiusProxies') { return @([PSCustomObject]@{ cn = @('zz-test-legacy-radius'); description = @('x [ZZ-TEST-seed]') }) }
                if ($Type -eq 'IdentityProviders') { return @([PSCustomObject]@{ cn = @('zz-test-github') }) }
                @()
            }
            $r = New-FreeIPAIdentityProvider -PassThru -Confirm:$false
            $r.UpdatedProxies | Should-Be 1
            $r.UpdatedIdps | Should-Be 1
            $r.CreatedProxies | Should-Be 1
            $r.CreatedIdps | Should-Be 1
            $mod = ($script:Calls | Where-Object { $_.Method -eq 'radiusproxy_mod' }).Options
            $mod.ContainsKey('ipatokenradiussecret') | Should-BeFalse
            $idpMod = ($script:Calls | Where-Object { $_.Method -eq 'idp_mod' }).Options
            $idpMod.ContainsKey('ipaidpclientsecret') | Should-BeFalse
            $idpMod.ContainsKey('ipaidpprovider') | Should-BeFalse
            $named = @($script:Calls | ForEach-Object { $_.Arguments[0] })
            @($named | Where-Object { $_ -notlike 'zz-test-*' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates nothing under -WhatIf, and refuses an unknown name' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAIdentityProvider -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
            { New-FreeIPAIdentityProvider -ProviderName nope -WhatIf } | Should-Throw -ExceptionMessage '*nope*'
        }
    }
}
