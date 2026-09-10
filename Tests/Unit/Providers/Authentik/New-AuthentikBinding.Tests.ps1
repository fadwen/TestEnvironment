#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A binding is a row of three references, and every one of them has to resolve to a seeded
    object or the grant lands on somebody else's application. These tests pin the resolution
    of each target kind and each subject kind, that a user subject is sent as the integer pk
    Authentik requires, that a rule is bound by its own pk, and that a re-run finds the
    existing binding by target and subject rather than stacking another.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:BindingRows = @(Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Authentik\Data\AuthentikBindings.csv') -Encoding UTF8)
    $script:EntitlementRows = @(Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Authentik\Data\AuthentikEntitlements.csv') -Encoding UTF8)
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikBinding' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ entitlements = $script:EntitlementRows } {
            param($entitlements)
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            $script:SeededEntitlements = @($entitlements | ForEach-Object {
                    [PSCustomObject]@{ pbm_uuid = "pbm-$($_.Application)-$($_.Name)"; name = "ZZ-TEST-$($_.Name)"; attributes = [PSCustomObject]@{ labKey = "$($_.Application)/$($_.Name)" } }
                })
            Mock Get-AuthentikSeededObject {
                switch ($Type) {
                    'Applications' { @('expenses', 'wiki', 'intranet', 'payroll', 'hidden-utility' | ForEach-Object { [PSCustomObject]@{ slug = "zz-test-$_"; pbm_uuid = "pbm-$_" } }) }
                    'Entitlements' { $script:SeededEntitlements }
                    'NotificationRules' { @([PSCustomObject]@{ pk = 'rule-alert'; name = 'ZZ-TEST-Alert Relay' }) }
                    'Groups' { @('All-Staff', 'Dept-Engineering', 'Contractors', 'Dept-Finance', 'Team-Platform', 'Lab-Admins' | ForEach-Object { [PSCustomObject]@{ pk = "g-$_"; attributes = [PSCustomObject]@{ labKey = $_ } } }) }
                    'Users' { @([PSCustomObject]@{ pk = 1; username = 'awhitfield' }, [PSCustomObject]@{ pk = 5; username = 'praghunathan' }, [PSCustomObject]@{ pk = 6; username = 'talvarez' }) }
                    'Policies' { @([PSCustomObject]@{ pk = 'pol-lf'; name = 'ZZ-TEST-Login Failures' }) }
                    default { @() }
                }
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/policies/bindings/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = "b-$($script:Created.Count)" }
                }
                return $null
            }
        }
    }

    It 'creates every binding, resolving each target and subject kind' {
        InModuleScope TestEnvironment -Parameters @{ expected = $script:BindingRows.Count } {
            param($expected)
            $r = New-AuthentikBinding -PassThru -Confirm:$false

            $r.TotalBindings | Should-Be $expected
            $r.CreatedBindings | Should-Be $expected
            $r.Errors | Should-BeCollection -Count 0

            $groupOnApp = $script:Created | Where-Object { $_.target -eq 'pbm-expenses' -and $_.group }
            $groupOnApp.group | Should-Be 'g-All-Staff'

            $userOnApp = $script:Created | Where-Object { $_.target -eq 'pbm-intranet' }
            $userOnApp.user | Should-Be 1
            ($userOnApp.user -is [int]) | Should-BeTrue

            $userOnEntitlement = $script:Created | Where-Object { $_.target -eq 'pbm-payroll-Administrator' }
            $userOnEntitlement.user | Should-Be 5

            $policyOnRule = $script:Created | Where-Object { $_.target -eq 'rule-alert' }
            $policyOnRule.policy | Should-Be 'pol-lf'
        }
    }

    It 'never sends more than one subject on a binding' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikBinding -Confirm:$false
            foreach ($body in $script:Created) {
                @(@('group', 'user', 'policy') | Where-Object { $body.ContainsKey($_) }).Count | Should-Be 1
            }
        }
    }

    It 'finds an existing binding by target and subject and does not stack another' {
        InModuleScope TestEnvironment {
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET') { return @([PSCustomObject]@{ pk = 'b-old'; group = 'g-Team-Platform'; user = $null; policy = $null }) }
                if ($Method -eq 'POST') { $script:Created.Add($Body); return [PSCustomObject]@{ pk = 'b-new' } }
                return $null
            }

            $r = New-AuthentikBinding -Target entitlement:wiki/Editor -PassThru -Confirm:$false

            $r.ExistingBindings | Should-Be 1
            $r.CreatedBindings | Should-Be 1
            $script:Created[0].user | Should-Be 6
        }
    }

    It 'reports a target or subject that does not exist and creates nothing for that row' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikBinding -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedBindings | Should-Be 0
            @($r.Errors).Count | Should-Be $r.TotalBindings
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikBinding -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
