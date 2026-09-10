#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A policy governs nothing until a binding attaches it to a target, and the target is the
    application's policy-binding UUID rather than the pk everything else uses. Bind to the
    wrong identifier and the policy is created, reported, and enforces nothing. These tests
    pin the target, the placeholder substitution that lets an expression name a seeded group,
    and that a re-run does not stack a second binding on the first.
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
                    )
                }
                @()
            }

            $script:PolicyBodies = [System.Collections.Generic.List[object]]::new()
            $script:BindingBodies = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/policies/expression/') {
                    $script:PolicyBodies.Add($Body)
                    return [PSCustomObject]@{ pk = "pol-$($script:PolicyBodies.Count)"; name = $Body.name }
                }
                if ($Method -eq 'POST' -and $Path -eq '/policies/bindings/') { $script:BindingBodies.Add($Body); return [PSCustomObject]@{ pk = 'b' } }
                return $null
            }
        }
    }

    It 'creates every policy and binds it to the application by its policy-binding UUID' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikPolicy -PassThru -Confirm:$false

            $r.CreatedPolicies | Should-Be 3
            $r.BindingsCreated | Should-Be 3
            @($script:BindingBodies | Where-Object { $_.target -notlike 'pbm-*' }) | Should-BeCollection -Count 0
            ($script:BindingBodies | Where-Object { $_.policy -eq 'pol-1' }).target | Should-Be 'pbm-payroll'
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
