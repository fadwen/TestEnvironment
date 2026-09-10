#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A policy governs nothing until a binding attaches it to a target, and the target is the
    application's policy-binding UUID rather than the pk everything else uses. Bind to the
    wrong identifier and the policy is created, reported, and enforces nothing. These tests
    pin the target, the placeholder substitution that lets an expression name a seeded group,
    and that a re-run does not stack a second binding on the first. The typed policies -
    password, reputation, GeoIP, event matcher - each go to their own endpoint with their
    settings typed the way the API demands, and a policy with no target is created unbound
    without that being an error.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikPolicy' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @(
                        [PSCustomObject]@{ slug = 'zz-test-payroll'; pbm_uuid = 'pbm-payroll' }
                        [PSCustomObject]@{ slug = 'zz-test-expenses'; pbm_uuid = 'pbm-expenses' }
                        [PSCustomObject]@{ slug = 'zz-test-intranet'; pbm_uuid = 'pbm-intranet' }
                    )
                }
                @()
            }

            $script:PolicyBodies = [System.Collections.Generic.List[object]]::new()
            $script:PolicyPaths = [System.Collections.Generic.List[string]]::new()
            $script:BindingBodies = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') { return @() }
                if ($Method -eq 'POST' -and $Path -like '/policies/*/' -and $Path -ne '/policies/bindings/') {
                    $script:PolicyBodies.Add($Body)
                    $script:PolicyPaths.Add($Path)
                    return [PSCustomObject]@{ pk = "pol-$($script:PolicyBodies.Count)"; name = $Body.name }
                }
                if ($Method -eq 'POST' -and $Path -eq '/policies/bindings/') { $script:BindingBodies.Add($Body); return [PSCustomObject]@{ pk = 'b' } }
                return $null
            }
        }
    }

    It 'creates every policy and binds the targeted ones to the application by its policy-binding UUID' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikPolicy -PassThru -Confirm:$false

            $r.CreatedPolicies | Should-Be 7
            $r.BindingsCreated | Should-Be 5
            $r.Errors | Should-BeCollection -Count 0
            @($script:BindingBodies | Where-Object { $_.target -notlike 'pbm-*' }) | Should-BeCollection -Count 0
            ($script:BindingBodies | Where-Object { $_.policy -eq 'pol-1' }).target | Should-Be 'pbm-payroll'
        }
    }

    It 'sends each typed policy to its own endpoint with its settings typed' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikPolicy -PolicyName 'Strong Password', 'Reputation Guard', 'Allowed Countries', 'Login Failures' -Confirm:$false

            $script:PolicyPaths | Should-BeCollection @('/policies/password/', '/policies/reputation/', '/policies/geoip/', '/policies/event_matcher/')

            $password = $script:PolicyBodies[0]
            $password.length_min | Should-Be 12
            ($password.length_min -is [int]) | Should-BeTrue
            $password.check_zxcvbn | Should-BeTrue
            $password.error_message | Should-MatchString ','
            $password.ContainsKey('expression') | Should-BeFalse

            $script:PolicyBodies[1].threshold | Should-Be -5
            @($script:PolicyBodies[2].countries) | Should-BeCollection @('US', 'GB', 'DE', 'CH', 'ES', 'JP')
            $script:PolicyBodies[3].action | Should-Be 'login_failed'
        }
    }

    It 'creates a policy with no target unbound, and that is not an error' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikPolicy -PolicyName 'Strong Password', 'Login Failures' -PassThru -Confirm:$false

            $r.BindingsCreated | Should-Be 0
            $r.Errors | Should-BeCollection -Count 0
            @($r.Policies | Where-Object Bound) | Should-BeCollection -Count 0
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -eq '/policies/bindings/' }
        }
    }

    It 'updates an existing policy at the endpoint its own type owns' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Policies') { return @([PSCustomObject]@{ pk = 'pol-geo'; name = 'ZZ-TEST-Allowed Countries'; meta_model_name = 'authentik_policies_geoip.geoippolicy' }) }
                @()
            }
            Mock Invoke-AuthentikRequest { if ($Method -eq 'PATCH') { return [PSCustomObject]@{ pk = 'pol-geo' } }; return @() }

            $r = New-AuthentikPolicy -PolicyName 'Allowed Countries' -SkipBinding -PassThru -Confirm:$false

            $r.UpdatedPolicies | Should-Be 1
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/policies/geoip/pol-geo/' }
        }
    }

    It 'refuses to turn an existing policy into a different type' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Policies') { return @([PSCustomObject]@{ pk = 'pol-x'; name = 'ZZ-TEST-Allowed Countries'; meta_model_name = 'authentik_policies_expression.expressionpolicy' }) }
                @()
            }

            $r = New-AuthentikPolicy -PolicyName 'Allowed Countries' -SkipBinding -PassThru -Confirm:$false -ErrorAction SilentlyContinue

            $r.UpdatedPolicies | Should-Be 0
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'Expression policy'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -in 'PATCH', 'POST' }
        }
    }

    It 'substitutes the prefix into an expression that names a seeded group' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikPolicy -PolicyName 'Finance Only' -Confirm:$false
            $script:PolicyBodies[0].expression | Should-MatchString 'name="ZZ-TEST-Department Finance"'
            $script:PolicyBodies[0].expression | Should-NotMatchString '\{prefix\}'
        }
    }

    It 'turns the literal line break in the CSV into a real one' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikPolicy -PolicyName 'Business Hours' -Confirm:$false
            $script:PolicyBodies[0].expression | Should-MatchString "import datetime`nreturn"
        }
    }

    It 'binds the business-hours policy disabled' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikPolicy -PolicyName 'Business Hours' -Confirm:$false
            $script:BindingBodies[0].enabled | Should-BeFalse
            $script:BindingBodies[0].target | Should-Be 'pbm-expenses'
        }
    }

    It 'does not stack a second binding on a re-run' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') { return @([PSCustomObject]@{ pk = 'existing' }) }
                if ($Method -eq 'POST' -and $Path -eq '/policies/expression/') { return [PSCustomObject]@{ pk = 'pol-1' } }
                if ($Method -eq 'POST' -and $Path -eq '/policies/bindings/') { $script:BindingBodies.Add($Body) }
                return $null
            }

            $r = New-AuthentikPolicy -PolicyName 'Deny Contractors' -PassThru -Confirm:$false

            $r.BindingsCreated | Should-Be 0
            $r.Policies[0].Bound | Should-BeTrue
        }
    }

    It 'reports a missing target and leaves the policy unbound' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikPolicy -PolicyName 'Deny Contractors' -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedPolicies | Should-Be 1
            $r.BindingsCreated | Should-Be 0
            @($r.Errors).Count | Should-Be 1
            $r.Policies[0].Bound | Should-BeFalse
        }
    }

    It 'creates no bindings under -SkipBinding' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikPolicy -SkipBinding -PassThru -Confirm:$false
            $r.BindingsCreated | Should-Be 0
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -eq '/policies/bindings/' }
        }
    }
}
