#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A role in Authentik is granted through a group, and a group's role list is replaced by a
    PATCH rather than appended to, so the one way to get this wrong is to hand a group a list
    that drops a role it already held. That merge is pinned, along with the permission grant
    by codename, the role held by nobody, and that a re-run finds the role rather than
    creating a second one under the same name.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikRole' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Groups') {
                    return @(
                        [PSCustomObject]@{ pk = 'g-admins'; name = 'ZZ-TEST-Lab Admins'; roles = @('someone-elses-role'); attributes = [PSCustomObject]@{ labKey = 'Lab-Admins' } }
                        [PSCustomObject]@{ pk = 'g-platform'; name = 'ZZ-TEST-Team Platform'; roles = @(); attributes = [PSCustomObject]@{ labKey = 'Team-Platform' } }
                    )
                }
                @()
            }

            $script:RoleBodies = [System.Collections.Generic.List[object]]::new()
            $script:Assigned = @{}
            $script:GroupPatches = @{}
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/rbac/roles/') {
                    $script:RoleBodies.Add($Body)
                    return [PSCustomObject]@{ pk = "role-$($script:RoleBodies.Count)"; name = $Body.name }
                }
                if ($Method -eq 'POST' -and $Path -like '/rbac/permissions/assigned_by_roles/*/assign/') {
                    $script:Assigned[$Path] = $Body.permissions
                    return $null
                }
                if ($Method -eq 'PATCH' -and $Path -like '/core/groups/*') { $script:GroupPatches[$Path] = $Body; return $null }
                return $null
            }
        }
    }

    It 'creates every role with the prefix and grants its permissions by codename' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikRole -PassThru -Confirm:$false

            $r.TotalRoles | Should-Be 3
            $r.CreatedRoles | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            @($script:RoleBodies | Where-Object { -not $_.name.StartsWith('ZZ-TEST-') }) | Should-BeCollection -Count 0
            @($script:Assigned['/rbac/permissions/assigned_by_roles/role-1/assign/']) | Should-ContainCollection @('authentik_core.reset_user_password')
            $r.PermissionsAssigned | Should-Be 7
        }
    }

    It 'merges the role into what the group already holds rather than replacing it' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikRole -RoleName Lab-Operator -Confirm:$false

            @($script:GroupPatches['/core/groups/g-admins/'].roles) | Should-BeCollection @('someone-elses-role', 'role-1')
        }
    }

    It 'assigns the unheld role to no group and says so' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikRole -RoleName Unassigned-Role -PassThru -Confirm:$false

            $r.GroupsAssigned | Should-Be 0
            $r.Roles[0].Groups | Should-BeCollection -Count 0
            $script:GroupPatches.Count | Should-Be 0
        }
    }

    It 'reports a group that does not exist and still creates the role' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikRole -RoleName App-Auditor -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedRoles | Should-Be 1
            @($r.Errors).Count | Should-Be 1
        }
    }

    It 'reuses a role that already exists and still assigns it' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Roles') { return @([PSCustomObject]@{ pk = 'role-existing'; name = 'ZZ-TEST-Application Auditor' }) }
                if ($Type -eq 'Groups') { return @([PSCustomObject]@{ pk = 'g-platform'; name = 'x'; roles = @(); attributes = [PSCustomObject]@{ labKey = 'Team-Platform' } }) }
                @()
            }

            $r = New-AuthentikRole -RoleName App-Auditor -PassThru -Confirm:$false

            $r.CreatedRoles | Should-Be 0
            $r.UpdatedRoles | Should-Be 1
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'POST' -and $Path -eq '/rbac/roles/' }
            @($script:GroupPatches['/core/groups/g-platform/'].roles) | Should-BeCollection @('role-existing')
        }
    }

    It 'touches no group under -SkipGroups' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikRole -SkipGroups -Confirm:$false
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikRole -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
