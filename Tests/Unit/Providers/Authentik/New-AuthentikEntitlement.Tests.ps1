#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    An entitlement belongs to an application and carries attributes, and both are evidence
    teardown relies on: the tag and the CSV key go into the attributes, and the application
    is resolved from the seeded set by slug so nothing is ever created on somebody else's
    application. A re-run finds the entitlement by its key rather than creating a second.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikEntitlement' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') {
                    return @('expenses', 'payroll', 'wiki', 'hidden-utility' | ForEach-Object {
                            [PSCustomObject]@{ pk = "app-$_"; slug = "zz-test-$_"; pbm_uuid = "pbm-$_" }
                        })
                }
                @()
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/core/application_entitlements/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pbm_uuid = "ent-$($script:Created.Count)"; name = $Body.name }
                }
                return [PSCustomObject]@{ pbm_uuid = 'ent-existing'; name = $Body.name }
            }
        }
    }

    It 'creates every entitlement on its seeded application with the prefix, the tag and its key' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikEntitlement -PassThru -Confirm:$false

            $r.TotalEntitlements | Should-Be 6
            $r.CreatedEntitlements | Should-Be 6
            $r.Errors | Should-BeCollection -Count 0
            @($script:Created | Where-Object { -not $_.name.StartsWith('ZZ-TEST-') }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.attributes.labSeedTag -ne 'ZZ-TEST-seed' }) | Should-BeCollection -Count 0
            ($script:Created | Where-Object { $_.attributes.labKey -eq 'payroll/Administrator' }).app | Should-Be 'app-payroll'
        }
    }

    It 'selects by Application/Name and refuses a key the CSV does not define' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikEntitlement -EntitlementName expenses/Approver -PassThru -Confirm:$false
            $r.Entitlements[0].Key | Should-Be 'expenses/Approver'
            $r.Entitlements[0].Application | Should-Be 'zz-test-expenses'

            { New-AuthentikEntitlement -EntitlementName expenses/Nothing -Confirm:$false } | Should-Throw -ExceptionMessage '*expenses/Nothing*'
        }
    }

    It 'skips an entitlement whose application does not exist and reports it' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikEntitlement -EntitlementName wiki/Reader -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedEntitlements | Should-Be 0
            @($r.Errors).Count | Should-Be 1
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'updates an entitlement that already exists rather than creating a second' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Applications') { return @([PSCustomObject]@{ pk = 'app-wiki'; slug = 'zz-test-wiki'; pbm_uuid = 'pbm-wiki' }) }
                if ($Type -eq 'Entitlements') { return @([PSCustomObject]@{ pbm_uuid = 'ent-existing'; name = 'ZZ-TEST-Editor'; attributes = [PSCustomObject]@{ labKey = 'wiki/Editor' } }) }
                @()
            }

            $r = New-AuthentikEntitlement -EntitlementName wiki/Editor -PassThru -Confirm:$false

            $r.UpdatedEntitlements | Should-Be 1
            $r.CreatedEntitlements | Should-Be 0
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/core/application_entitlements/ent-existing/' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikEntitlement -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
