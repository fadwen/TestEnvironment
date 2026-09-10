#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    An application is a thin object over a provider, and the provider is where the
    integration-shaped mistakes live: a redirect that should be a regex sent as strict, a
    proxy without an external host, a flow UUID that had to come from the instance. These
    tests assert the bodies sent for each provider type, that the seed domain is substituted,
    and that the application carries the marker teardown proves ownership by.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikApplication' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject { @() }
            Mock Get-AuthentikFlow { if ($Designation -eq 'authorization') { 'flow-auth' } else { 'flow-inv' } }
            Mock Get-AuthentikSigningKeypair { 'kp-seeded' }
            # The instance's own default mappings, by managed id, the way the helper resolves them.
            Mock Get-AuthentikManagedMapping { @($Managed | ForEach-Object { "pm-$($_.Split('/')[-1])" }) }

            $script:Providers = [System.Collections.Generic.List[object]]::new()
            $script:Applications = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -like '/providers/*') {
                    $script:Providers.Add([PSCustomObject]@{ Path = $Path; Body = $Body })
                    return [PSCustomObject]@{ pk = $script:Providers.Count; name = $Body.name }
                }
                if ($Method -eq 'POST' -and $Path -eq '/core/applications/') {
                    $script:Applications.Add($Body)
                    return [PSCustomObject]@{ pk = "app-$($Body.slug)"; pbm_uuid = "pbm-$($Body.slug)"; slug = $Body.slug }
                }
                return $null
            }
        }
    }

    It 'creates every application with the slug prefix and the marker in its description' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikApplication -PassThru -Confirm:$false

            $r.TotalApplications | Should-Be 9
            $r.CreatedApplications | Should-Be 9
            $r.ProvidersCreated | Should-Be 8
            $r.Errors | Should-BeCollection -Count 0
            @($script:Applications | Where-Object { -not $_.slug.StartsWith('zz-test-') }) | Should-BeCollection -Count 0
            @($script:Applications | Where-Object { -not $_.meta_description.EndsWith('[ZZ-TEST-seed]') }) | Should-BeCollection -Count 0
        }
    }

    It 'sends a strict redirect for the confidential client and a regex for the wildcard one' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Expense Portal', 'Engineering Wiki' -Confirm:$false

            $expenses = ($script:Providers | Where-Object { $_.Body.name -like '*Expense*' }).Body
            $expenses.client_type | Should-Be 'confidential'
            $expenses.redirect_uris[0].matching_mode | Should-Be 'strict'
            $expenses.redirect_uris[0].url | Should-Be 'https://expenses.lab.example.com/oauth/callback'
            $expenses.authorization_flow | Should-Be 'flow-auth'
            $expenses.invalidation_flow | Should-Be 'flow-inv'

            $wiki = ($script:Providers | Where-Object { $_.Body.name -like '*Wiki*' }).Body
            $wiki.client_type | Should-Be 'public'
            $wiki.redirect_uris[0].matching_mode | Should-Be 'regex'
        }
    }

    It 'gives every provider the default mappings the admin UI would, so a client can sign in through it' {
        # The API attaches none. A provider with no openid, email and profile scopes issues a
        # token with no claims, which is a provider nothing can sign in through.
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Expense Portal', 'Intranet Portal', 'Partner Portal' -Confirm:$false

            $oauth = ($script:Providers | Where-Object { $_.Path -eq '/providers/oauth2/' }).Body
            @($oauth.property_mappings) | Should-BeCollection @('pm-scope-openid', 'pm-scope-email', 'pm-scope-profile')

            $proxy = ($script:Providers | Where-Object { $_.Path -eq '/providers/proxy/' }).Body
            @($proxy.property_mappings) | Should-BeCollection @('pm-scope-openid', 'pm-scope-email', 'pm-scope-profile', 'pm-scope-proxy')

            $saml = ($script:Providers | Where-Object { $_.Path -eq '/providers/saml/' }).Body
            @($saml.property_mappings) | Should-BeCollection @('pm-upn', 'pm-name', 'pm-email', 'pm-username', 'pm-uid', 'pm-groups')
        }
    }

    It 'still creates the provider when the instance lacks a default mapping' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikManagedMapping { @() }

            $r = New-AuthentikApplication -ApplicationName 'Expense Portal' -PassThru -Confirm:$false

            $r.ProvidersCreated | Should-Be 1
            $r.Errors | Should-BeCollection -Count 0
            ($script:Providers[0].Body.property_mappings -is [array]) | Should-BeTrue
            @($script:Providers[0].Body.property_mappings).Count | Should-Be 0
        }
    }

    It 'creates a proxy provider with the external host on the seed domain substituted' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Intranet Portal' -Confirm:$false

            $script:Providers[0].Path | Should-Be '/providers/proxy/'
            $script:Providers[0].Body.external_host | Should-Be 'https://intranet.lab.example.com'
            # Required by the server in proxy mode, whatever the schema says.
            $script:Providers[0].Body.internal_host | Should-Be 'http://intranet-backend.internal:8080'
            $script:Providers[0].Body.mode | Should-Be 'proxy'
            $script:Applications[0].meta_launch_url | Should-Be 'https://intranet.lab.example.com'
        }
    }

    It 'creates a SAML provider signed by the seeded keypair, with its URLs on the connection domain' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Partner Portal' -Confirm:$false

            $script:Providers[0].Path | Should-Be '/providers/saml/'
            $saml = $script:Providers[0].Body
            $saml.acs_url | Should-Be 'https://partner.lab.example.com/saml/acs'
            $saml.audience | Should-Be 'https://partner.lab.example.com'
            $saml.sp_binding | Should-Be 'post'
            $saml.sign_assertion | Should-BeTrue
            $saml.sign_response | Should-BeFalse
            $saml.signing_kp | Should-Be 'kp-seeded'
            $saml.authorization_flow | Should-Be 'flow-auth'
        }
    }

    It 'creates an LDAP provider with its base DN and typed numbers' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Directory Gateway' -Confirm:$false

            $script:Providers[0].Path | Should-Be '/providers/ldap/'
            $ldap = $script:Providers[0].Body
            $ldap.base_dn | Should-Be 'DC=zz-test,DC=lab'
            $ldap.search_mode | Should-Be 'cached'
            $ldap.uid_start_number | Should-Be 4000
            ($ldap.uid_start_number -is [int]) | Should-BeTrue
            $script:Applications[0].ContainsKey('meta_launch_url') | Should-BeFalse
            $script:Applications[0].meta_hide | Should-BeTrue
        }
    }

    It 'creates a RADIUS provider with a generated secret that the CSV never held and comma-joined networks' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Network Access' -Confirm:$false

            $script:Providers[0].Path | Should-Be '/providers/radius/'
            $radius = $script:Providers[0].Body
            $radius.client_networks | Should-Be '10.0.0.0/8,192.168.0.0/16'
            $radius.mfa_support | Should-BeTrue
            $radius.shared_secret.Length | Should-BeGreaterThan 15
            (Get-Content (Join-Path (Get-AuthentikDataPath) 'AuthentikApplications.csv') -Raw) | Should-NotMatchString 'shared_secret'
        }
    }

    It 'creates the provider-less application with no provider and no launch URL' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikApplication -ApplicationName 'Legacy Reporting Tool' -PassThru -Confirm:$false

            $script:Providers.Count | Should-Be 0
            $null -eq $script:Applications[0].provider | Should-BeTrue
            $script:Applications[0].ContainsKey('meta_launch_url') | Should-BeFalse
            $r.Applications[0].ProviderType | Should-Be 'None'
        }
    }

    It 'hides the hidden one' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikApplication -ApplicationName 'Hidden Utility' -Confirm:$false
            $script:Applications[0].meta_hide | Should-BeTrue
        }
    }

    It 'creates no providers under -SkipProvider' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikApplication -SkipProvider -PassThru -Confirm:$false
            $r.ProvidersCreated | Should-Be 0
            Should-NotInvoke Get-AuthentikFlow
        }
    }

    It 'reuses a provider that already exists' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Providers') { return @([PSCustomObject]@{ pk = 77; name = 'ZZ-TEST-Expense Portal Provider' }) }
                @()
            }

            $r = New-AuthentikApplication -ApplicationName 'Expense Portal' -PassThru -Confirm:$false

            $r.ProvidersCreated | Should-Be 0
            $script:Applications[0].provider | Should-Be 77
        }
    }
}
