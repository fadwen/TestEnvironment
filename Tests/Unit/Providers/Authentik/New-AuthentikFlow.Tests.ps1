#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Flows are what people sign in with, so the property that matters most is the one with no
    parameter: the seed never creates, edits or binds anything to a flow whose slug lacks the
    prefix, and never writes to the brand, so the instance's default flows and the flows a
    real user lands on are never touched. A seeded flow is reached only through a seeded
    provider or its own URL. That is pinned first, then the rest: stages by type at their own
    endpoints with typed settings, bindings in CSV order without stacking on a re-run, and the
    flow attached to a provider at the field its designation dictates.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikFlow' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @(
                        [PSCustomObject]@{ slug = 'zz-test-partner'; provider = 31; provider_obj = [PSCustomObject]@{ component = 'ak-provider-saml-form' } }
                        [PSCustomObject]@{ slug = 'zz-test-intranet'; provider = 32; provider_obj = [PSCustomObject]@{ component = 'ak-provider-proxy-form' } }
                        [PSCustomObject]@{ slug = 'zz-test-expenses'; provider = 33; provider_obj = [PSCustomObject]@{ component = 'ak-provider-oauth2-form' } }
                    )
                }
                @()
            }

            $script:Requests = [System.Collections.Generic.List[object]]::new()
            $script:Stages = @{}
            Mock Invoke-AuthentikRequest {
                $script:Requests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body; Query = $Query })
                if ($Method -eq 'POST' -and $Path -like '/stages/*') {
                    $pk = "stage-$($Body.name)"
                    return [PSCustomObject]@{ pk = $pk; name = $Body.name }
                }
                if ($Method -eq 'POST' -and $Path -eq '/flows/instances/') { return [PSCustomObject]@{ pk = "flow-$($Body.slug)"; slug = $Body.slug } }
                if ($Method -eq 'GET' -and $Path -eq '/flows/bindings/') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/flows/bindings/') { return [PSCustomObject]@{ pk = 'fsb' } }
                if ($Method -eq 'GET' -and $Path -eq '/providers/proxy/32/') {
                    return [PSCustomObject]@{ pk = 32; external_host = 'https://intranet.lab.example.com'; internal_host = 'http://intranet-backend.internal:8080'; mode = 'proxy'; internal_host_ssl_validation = $true }
                }
                return $null
            }
        }
    }

    Context 'Nothing the instance already has is ever touched, and there is no parameter to change that' {

        It 'never writes to the brand and never writes a flow without the seed prefix' {
            InModuleScope TestEnvironment {
                $null = New-AuthentikFlow -Confirm:$false

                @($script:Requests | Where-Object { $_.Path -like '/core/brands*' }) | Should-BeCollection -Count 0
                $writes = @($script:Requests | Where-Object { $_.Method -ne 'GET' -and $_.Path -like '/flows/instances/*' })
                $writes.Count | Should-BeGreaterThan 0
                @($writes | Where-Object { $_.Path -ne '/flows/instances/' -and $_.Path -notlike '/flows/instances/zz-test-*' }) | Should-BeCollection -Count 0
                @($writes | Where-Object { $_.Body -and $_.Body.slug -and -not $_.Body.slug.StartsWith('zz-test-') }) | Should-BeCollection -Count 0
            }
        }

        It 'binds stages only to seeded flows and attaches flows only to seeded providers' {
            InModuleScope TestEnvironment {
                $null = New-AuthentikFlow -Confirm:$false

                @($script:Requests | Where-Object { $_.Path -eq '/flows/bindings/' -and $_.Method -eq 'POST' -and $_.Body.target -notlike 'flow-zz-test-*' }) | Should-BeCollection -Count 0
                $providerPatches = @($script:Requests | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -like '/providers/*' })
                $providerPatches.Count | Should-Be 3
                @($providerPatches | Where-Object { $_.Path -notin '/providers/saml/31/', '/providers/proxy/32/', '/providers/oauth2/33/' }) | Should-BeCollection -Count 0
            }
        }

        It 'offers no way to make a seeded flow the default for anyone' {
            $command = Get-Command New-AuthentikFlow
            $command.Parameters.Keys | Should-NotContainCollection @('Default')
            $command.Parameters.Keys | Should-NotContainCollection @('SetBrand')
            $command.Parameters.Keys | Should-NotContainCollection @('Brand')
        }
    }

    It 'creates each stage at the endpoint its type owns, with its settings typed' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikFlow -SkipProvider -PassThru -Confirm:$false

            $r.StagesCreated | Should-Be 6
            $r.Errors | Should-BeCollection -Count 0
            $paths = @($script:Requests | Where-Object { $_.Method -eq 'POST' -and $_.Path -like '/stages/*' } | ForEach-Object { $_.Path })
            $paths | Should-BeCollection @('/stages/identification/', '/stages/password/', '/stages/authenticator/validate/', '/stages/consent/', '/stages/user_login/', '/stages/deny/')

            $identify = ($script:Requests | Where-Object { $_.Path -eq '/stages/identification/' }).Body
            @($identify.user_fields) | Should-BeCollection @('username', 'email')
            $identify.pretend_user_exists | Should-BeTrue

            $password = ($script:Requests | Where-Object { $_.Path -eq '/stages/password/' }).Body
            # One backend in the CSV still has to arrive as a list, or the API refuses it.
            ($password.backends -is [array]) | Should-BeTrue
            @($password.backends) | Should-BeCollection @('authentik.core.auth.InbuiltBackend')
            $password.failed_attempts_before_cancel | Should-Be 3

            $mfa = ($script:Requests | Where-Object { $_.Path -eq '/stages/authenticator/validate/' }).Body
            @($mfa.device_classes) | Should-BeCollection @('static', 'totp', 'webauthn')
            $mfa.not_configured_action | Should-Be 'skip'
        }
    }

    It 'binds the stages in CSV order, ten apart, and reports them' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikFlow -FlowName Partner-Authentication -SkipProvider -PassThru -Confirm:$false

            $bindings = @($script:Requests | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/flows/bindings/' })
            $bindings.Count | Should-Be 4
            @($bindings | ForEach-Object { $_.Body.order }) | Should-BeCollection @(0, 10, 20, 30)
            @($bindings | ForEach-Object { $_.Body.stage }) | Should-BeCollection @('stage-ZZ-TEST-Identify', 'stage-ZZ-TEST-Password', 'stage-ZZ-TEST-Second Factor', 'stage-ZZ-TEST-Log In')
            $r.Flows[0].Stages | Should-BeCollection @('Identify', 'Password', 'Second-Factor', 'Log-In')
            $r.Flows[0].Slug | Should-Be 'zz-test-partner-authentication'
        }
    }

    It 'creates only the stages a selected flow uses' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikFlow -FlowName Contractor-Enrolment -SkipProvider -PassThru -Confirm:$false
            $r.StagesCreated | Should-Be 1
            ($script:Requests | Where-Object { $_.Path -eq '/stages/deny/' }).Body.deny_message | Should-MatchString 'Contractors'
        }
    }

    It 'attaches each flow at the field its designation dictates' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikFlow -PassThru -Confirm:$false

            $saml = ($script:Requests | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -eq '/providers/saml/31/' }).Body
            $saml.authentication_flow | Should-Be 'flow-zz-test-partner-authentication'
            $saml.ContainsKey('authorization_flow') | Should-BeFalse

            $oauth = ($script:Requests | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -eq '/providers/oauth2/33/' }).Body
            $oauth.authorization_flow | Should-Be 'flow-zz-test-consented-authorization'

            # A proxy provider is validated whole on update, so its hosts have to ride along.
            $proxy = ($script:Requests | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -eq '/providers/proxy/32/' }).Body
            $proxy.authentication_flow | Should-Be 'flow-zz-test-partner-authentication'
            $proxy.internal_host | Should-Be 'http://intranet-backend.internal:8080'
            $proxy.external_host | Should-Be 'https://intranet.lab.example.com'
            $proxy.mode | Should-Be 'proxy'

            $r.ProvidersUpdated | Should-Be 3
            ($r.Flows | Where-Object Key -eq 'Contractor-Enrolment').Applications | Should-BeCollection -Count 0
        }
    }

    It 'does not stack a binding on a re-run and updates the flow by slug' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Flows') { return @([PSCustomObject]@{ pk = 'flow-existing'; slug = 'zz-test-contractor-enrolment' }) }
                if ($Type -eq 'Stages') { return @([PSCustomObject]@{ pk = 'stage-existing'; name = 'ZZ-TEST-Refuse'; meta_model_name = 'authentik_stages_deny.denystage' }) }
                @()
            }
            Mock Invoke-AuthentikRequest {
                $script:Requests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                if ($Method -eq 'PATCH' -and $Path -like '/stages/deny/*') { return [PSCustomObject]@{ pk = 'stage-existing' } }
                if ($Method -eq 'PATCH' -and $Path -eq '/flows/instances/zz-test-contractor-enrolment/') { return [PSCustomObject]@{ pk = 'flow-existing'; slug = 'zz-test-contractor-enrolment' } }
                if ($Method -eq 'GET' -and $Path -eq '/flows/bindings/') { return @([PSCustomObject]@{ pk = 'fsb-old'; stage = 'stage-existing' }) }
                return $null
            }

            $r = New-AuthentikFlow -FlowName Contractor-Enrolment -SkipProvider -PassThru -Confirm:$false

            $r.UpdatedFlows | Should-Be 1
            $r.StagesUpdated | Should-Be 1
            $r.BindingsCreated | Should-Be 0
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'moves an existing binding to the order the CSV gives it rather than duplicating it' {
        InModuleScope TestEnvironment {
            # A previous run created Identify and Log In but the Password stage failed, so Log
            # In sits at order 10. This run must put Password at 10 and move Log In to 30.
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Flows') { return @([PSCustomObject]@{ pk = 'flow-existing'; slug = 'zz-test-partner-authentication' }) }
                @()
            }
            Mock Invoke-AuthentikRequest {
                $script:Requests.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                if ($Method -eq 'POST' -and $Path -like '/stages/*') { return [PSCustomObject]@{ pk = "stage-$($Body.name)" } }
                if ($Method -eq 'PATCH' -and $Path -like '/flows/instances/*') { return [PSCustomObject]@{ pk = 'flow-existing'; slug = 'zz-test-partner-authentication' } }
                if ($Method -eq 'GET' -and $Path -eq '/flows/bindings/') {
                    return @(
                        [PSCustomObject]@{ pk = 'fsb-identify'; stage = 'stage-ZZ-TEST-Identify'; order = 0 }
                        [PSCustomObject]@{ pk = 'fsb-login'; stage = 'stage-ZZ-TEST-Log In'; order = 10 }
                    )
                }
                if ($Method -eq 'POST' -and $Path -eq '/flows/bindings/') { return [PSCustomObject]@{ pk = 'fsb-new' } }
                return $null
            }

            $r = New-AuthentikFlow -FlowName Partner-Authentication -SkipProvider -PassThru -Confirm:$false

            $r.BindingsCreated | Should-Be 2
            $created = @($script:Requests | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/flows/bindings/' })
            @($created | ForEach-Object { "$($_.Body.stage)=$($_.Body.order)" }) | Should-BeCollection @('stage-ZZ-TEST-Password=10', 'stage-ZZ-TEST-Second Factor=20')
            $moved = @($script:Requests | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -eq '/flows/bindings/fsb-login/' })
            $moved.Count | Should-Be 1
            $moved[0].Body.order | Should-Be 30
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/flows/bindings/fsb-identify/' }
        }
    }

    It 'refuses to turn an existing stage into a different type' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Stages') { return @([PSCustomObject]@{ pk = 's'; name = 'ZZ-TEST-Refuse'; meta_model_name = 'authentik_stages_password.passwordstage' }) }
                @()
            }

            $r = New-AuthentikFlow -FlowName Contractor-Enrolment -SkipProvider -PassThru -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            @($r.Errors | Where-Object { $_ -like '*Password stage*' }).Count | Should-Be 1
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -like '/stages/*' -and $Method -ne 'GET' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikFlow -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
