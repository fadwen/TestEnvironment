#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The orchestrator's job is ordering and honesty. Groups must exist before users join them,
    host groups before hosts join them, and the directory before every access layer that
    names it, so the order is asserted rather than assumed. And a step that returned an
    object full of errors has not succeeded, whatever the absence of an exception suggests,
    so the failure count is asserted against the Errors property. The backstop mock is the
    reason this suite can never reach a realm: a step added later and left unmocked throws
    rather than calling out.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPAEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com' } }
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Test-FreeIPAPrerequisite { $true }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-FreeIPAGroup { $script:StepOrder.Add('Groups'); [PSCustomObject]@{ CreatedGroups = 102; UpdatedGroups = 0; NestingsApplied = 40; Errors = @() } }
            Mock New-FreeIPAIdentityProvider { $script:StepOrder.Add('IdentityProviders'); [PSCustomObject]@{ CreatedProxies = 2; CreatedIdps = 2; Errors = @() } }
            Mock New-FreeIPAUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ CreatedUsers = 333; UpdatedUsers = 0; MembershipsApplied = 100; Errors = @() } }
            Mock New-FreeIPAHostgroup { $script:StepOrder.Add('Hostgroups'); [PSCustomObject]@{ CreatedHostgroups = 30; UpdatedHostgroups = 0; NestingsApplied = 8; Errors = @() } }
            Mock New-FreeIPADnsZone { $script:StepOrder.Add('Dns'); [PSCustomObject]@{ DnsEnabled = $true; ZonesCreated = 2; RecordsCreated = 11; Errors = @() } }
            Mock New-FreeIPAHost { $script:StepOrder.Add('Hosts'); [PSCustomObject]@{ CreatedHosts = 413; UpdatedHosts = 0; MembershipsApplied = 30; Errors = @() } }
            Mock New-FreeIPANetgroup { $script:StepOrder.Add('Netgroups'); [PSCustomObject]@{ CreatedNetgroups = 4; MembershipsApplied = 6; Errors = @() } }
            Mock New-FreeIPAHbacRule { $script:StepOrder.Add('HbacRules'); [PSCustomObject]@{ CreatedRules = 7; ServicesCreated = 3; ServiceGroupsCreated = 3; Errors = @() } }
            Mock New-FreeIPASudoRule { $script:StepOrder.Add('SudoRules'); [PSCustomObject]@{ CreatedRules = 7; CommandsCreated = 8; CommandsReused = 0; Errors = @() } }
            Mock New-FreeIPARole { $script:StepOrder.Add('Roles'); [PSCustomObject]@{ CreatedRoles = 4; PrivilegesCreated = 3; PermissionsCreated = 3; Errors = @() } }
            Mock New-FreeIPAPasswordPolicy { $script:StepOrder.Add('PasswordPolicies'); [PSCustomObject]@{ CreatedPolicies = 3; UpdatedPolicies = 0; Errors = @() } }
            Mock New-FreeIPAService { $script:StepOrder.Add('Services'); [PSCustomObject]@{ CreatedServices = 4; DelegationRulesCreated = 1; DelegationTargetsCreated = 2; Errors = @() } }
            Mock New-FreeIPAIdView { $script:StepOrder.Add('IdViews'); [PSCustomObject]@{ CreatedViews = 2; OverridesCreated = 4; HostsApplied = 1; Errors = @() } }
            Mock New-FreeIPAOtpToken { $script:StepOrder.Add('OtpTokens'); [PSCustomObject]@{ CreatedTokens = 4; UpdatedTokens = 0; Errors = @() } }
            Mock New-FreeIPAAutomemberRule { $script:StepOrder.Add('AutomemberRules'); [PSCustomObject]@{ CreatedRules = 5; ConditionsApplied = 6; EntriesRebuilt = 744; Errors = @() } }
            Mock New-FreeIPAAutomount { $script:StepOrder.Add('Automount'); [PSCustomObject]@{ LocationsCreated = 1; MapsCreated = 2; KeysCreated = 3; Errors = @() } }
            Mock New-FreeIPASelinuxUserMap { $script:StepOrder.Add('SelinuxUserMaps'); [PSCustomObject]@{ CreatedMaps = 3; MembershipsApplied = 4; Errors = @() } }
            Mock New-FreeIPACertMapRule { $script:StepOrder.Add('CertMapRules'); [PSCustomObject]@{ CreatedRules = 3; UpdatedRules = 0; Errors = @() } }
            Mock New-FreeIPACaAcl { $script:StepOrder.Add('CaAcls'); [PSCustomObject]@{ CreatedAcls = 4; MembershipsApplied = 8; Errors = @() } }
            Mock New-FreeIPACertificate { $script:StepOrder.Add('Certificates'); [PSCustomObject]@{ Issued = 10; Revoked = 3; Existing = 0; Errors = @() } }

            # The backstop. A step added later and not mocked here throws rather than reaching
            # whatever realm the developer is pointed at.
            Mock Invoke-FreeIPARequest { throw "A network call escaped the mocks: $Method" }
            Mock Send-FreeIPAHttpRequest { throw "A network call escaped the mocks: $Path" }
        }
    }

    It 'runs the steps in dependency order' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPAEnvironment -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Groups', 'IdentityProviders', 'Users', 'Hostgroups', 'Dns', 'Hosts', 'Netgroups', 'HbacRules', 'SudoRules', 'Roles', 'PasswordPolicies', 'Services', 'IdViews', 'OtpTokens', 'AutomemberRules', 'Automount', 'SelinuxUserMaps', 'CertMapRules', 'CaAcls', 'Certificates')
        }
    }

    It 'skips what it is told to and attempts the rest' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPAEnvironment -Skip Hosts, Hostgroups, Dns, IdentityProviders, Services, IdViews, OtpTokens, AutomemberRules, Automount, SelinuxUserMaps, CertMapRules, CaAcls, Certificates -PassThru -Confirm:$false
            $script:StepOrder | Should-BeCollection @('Groups', 'Users', 'Netgroups', 'HbacRules', 'SudoRules', 'Roles', 'PasswordPolicies')
            $r.Operations.Hosts.Attempted | Should-BeFalse
            $r.Summary.TotalOperations | Should-Be 7
            $r.Summary.SuccessfulOperations | Should-Be 7
        }
    }

    It 'forwards the account password and progress switch to the users step only' {
        InModuleScope TestEnvironment {
            $password = New-Object System.Security.SecureString
            $null = New-FreeIPAEnvironment -AccountPassword $password -ShowProgress -Confirm:$false
            Should-Invoke New-FreeIPAUser -Times 1 -Exactly -ParameterFilter { $null -ne $AccountPassword -and $ShowProgress }
            Should-Invoke New-FreeIPAGroup -Times 1 -Exactly -ParameterFilter { $ShowProgress }
        }
    }

    It 'counts a step that reported errors as failed, and a step that threw, and still runs the rest' {
        InModuleScope TestEnvironment {
            Mock New-FreeIPAUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ CreatedUsers = 300; UpdatedUsers = 0; MembershipsApplied = 0; Errors = @('Failed to create user ''x'': boom') } }
            Mock New-FreeIPAHostgroup { $script:StepOrder.Add('Hostgroups'); throw 'host groups exploded' }

            $r = New-FreeIPAEnvironment -PassThru -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            $script:StepOrder.Count | Should-Be 20
            $r.Summary.FailedOperations | Should-Be 2
            $r.Summary.SuccessfulOperations | Should-Be 18
            $r.Operations.Users.Success | Should-BeFalse
            $r.Operations.Hostgroups.Results | Should-Be 'host groups exploded'
        }
    }

    It 'refuses to start when the prerequisites are not met' {
        InModuleScope TestEnvironment {
            Mock Test-FreeIPAPrerequisite { $false }
            { New-FreeIPAEnvironment -Confirm:$false } | Should-Throw -ExceptionMessage '*Prerequisites not met*'
            $script:StepOrder.Count | Should-Be 0
        }
    }
}
