#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the tenant when a name came back wrong. So the tenant here is built
    from the module's own seed files by the rules the seed applies - a UPN from the prefix, the key
    and the suffix; groups, devices and applications behind the prefix; members read in one batch
    per group - and the verifier must pass against it. Then one user is removed, one display name
    is swapped for its decomposed twin that -eq calls equal, one group is added that the data never
    names, and one membership is dropped, and every one of those must be named in the result.

    The licence-gated types are counted and never judged, because a tenant without P2 is not a
    fault of the seed.

    Everything is mocked. The tenant is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Test-EntraEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Get-EntraConnection { @{ TenantId = 'tenant-1'; UpnSuffix = 'lab.example.com'; AuthType = 'ClientAssertion' } }
            Mock Get-EntraSeedMarker { [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; Tag = 'ZZ-TEST-seed'; UpnSuffix = 'lab.example.com' } }

            $userRows = @(Get-EntraSeedData -Name EntraUsers)
            $guestRows = @(Get-EntraSeedData -Name EntraGuestUsers)
            $groupRows = @(Get-EntraSeedData -Name EntraGroups)
            $deviceRows = @(Get-EntraSeedData -Name EntraDevices)
            $applicationRows = @(Get-EntraSeedData -Name EntraApplications)

            $upn = { param($key) 'ZZ-TEST-{0}@lab.example.com' -f $key }
            $script:Fixture = @{
                Users                     = [System.Collections.Generic.List[object]]@(
                    @($userRows | ForEach-Object { [PSCustomObject]@{ id = "u-$($_.Key)"; userPrincipalName = & $upn $_.Key; displayName = $_.DisplayName; userType = 'Member' } }) +
                    @($guestRows | ForEach-Object { [PSCustomObject]@{ id = "guest-$($_.Key)"; userPrincipalName = "zz-test-$($_.Key)_example.com#EXT#@lab.example.com"; displayName = $_.DisplayName; userType = 'Guest' } })
                )
                Groups                    = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object { [PSCustomObject]@{ id = "g-$($_.Key)"; displayName = 'ZZ-TEST-{0}' -f $_.DisplayName } })
                Devices                   = @($deviceRows | ForEach-Object { [PSCustomObject]@{ id = "d-$($_.Key)"; displayName = 'ZZ-TEST-{0}' -f $_.DisplayName } })
                # The schema application that carries the directory extensions is seeded by the
                # extension step and named by no row.
                Applications              = @($applicationRows | ForEach-Object { [PSCustomObject]@{ id = "a-$($_.Key)"; displayName = 'ZZ-TEST-{0}' -f $_.DisplayName } }) +
                    @([PSCustomObject]@{ id = 'a-schema'; displayName = 'ZZ-TEST-Schema' })
                ConditionalAccessPolicies = @([PSCustomObject]@{ id = 'ca-1'; displayName = 'ZZ-TEST-Report only' })
            }

            # Members as the directory answers them: a user by UPN, a nested group by display name.
            $groupNameByKey = @{}
            foreach ($row in $groupRows) { $groupNameByKey[$row.Key] = 'ZZ-TEST-{0}' -f $row.DisplayName }
            $script:MembersByGroupId = @{}
            foreach ($row in $groupRows) {
                $script:MembersByGroupId["g-$($row.Key)"] = [System.Collections.Generic.List[object]]@(
                    @($row.Members -split ';' | Where-Object { $_ } | ForEach-Object { [PSCustomObject]@{ id = "u-$_"; userPrincipalName = & $upn $_; displayName = 'x' } }) +
                    @($row.MemberGroups -split ';' | Where-Object { $_ } | ForEach-Object { [PSCustomObject]@{ id = "g-$_"; displayName = $groupNameByKey[$_] } })
                )
            }
            $script:UserRows = $userRows
            $script:GuestRows = $guestRows
            $script:StaticGroups = @($groupRows | Where-Object { $_.MembershipType -ne 'Dynamic' -and ($_.Members -or $_.MemberGroups) }).Count
            $script:ExpectedPairs = @($groupRows | Where-Object { $_.MembershipType -ne 'Dynamic' } | ForEach-Object {
                    @($_.Members -split ';' | Where-Object { $_ }) + @($_.MemberGroups -split ';' | Where-Object { $_ })
                }).Count

            Mock Get-EntraSeededObject {
                if ($script:Fixture.ContainsKey($Type)) { return @($script:Fixture[$Type]) }
                @()
            }
            Mock Invoke-EntraBatch {
                foreach ($item in @($Request)) {
                    if ($item.Url -notmatch '^/groups/(.+?)/members') { throw "Unexpected batch request $($item.Url)" }
                    [PSCustomObject]@{ Reference = $item.Reference; Success = $true; Status = 200; Body = [PSCustomObject]@{ value = $script:MembersByGroupId[$matches[1]].ToArray() } }
                }
            }
            Mock Invoke-EntraRequest { throw "Unexpected request $Method $Path" }
        }
    }

    It 'passes against a tenant that holds exactly what the data describes, and counts what the licence decides' {
        InModuleScope TestEnvironment {
            $result = Test-EntraEnvironment -Quiet

            $result.Provider | Should-Be 'Entra'
            $result.Target | Should-Be 'tenant-1'
            $result.Passed | Should-BeTrue
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            ($result.Checks | Where-Object { $_.Name -eq 'Users' }).Expected | Should-Be $script:UserRows.Count
            $guests = $result.Checks | Where-Object { $_.Name -eq 'Guests' }
            $guests.Kind | Should-Be 'Count'
            $guests.Expected | Should-Be $script:GuestRows.Count
            $guests.Passed | Should-BeTrue
            ($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }).Expected | Should-Be $script:ExpectedPairs

            $policies = $result.Checks | Where-Object { $_.Name -eq 'ConditionalAccessPolicies' }
            $policies.Found | Should-Be 1
            $policies.Passed | Should-BeNull
            ($result.Checks | Where-Object { $_.Name -eq 'RoleEligibilities' }).Found | Should-Be 0

            # One batch, one request per static group with members, never a request per member.
            Should-Invoke Invoke-EntraBatch -Times 1 -Exactly -ParameterFilter { @($Request).Count -eq $script:StaticGroups }
        }
    }

    It 'names a missing user, a name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            $gone = $script:Fixture.Users | Where-Object { $_.userPrincipalName -eq 'ZZ-TEST-awhitfield@lab.example.com' }
            $null = $script:Fixture.Users.Remove($gone)

            $jose = $script:Fixture.Users | Where-Object { $_.userPrincipalName -eq 'ZZ-TEST-jnino@lab.example.com' }
            $decomposed = 'Jose' + [string][char]0x0301 + ' Nin' + [string][char]0x0303 + 'o'
            ($decomposed -eq $jose.displayName) | Should-BeTrue
            $jose.displayName = $decomposed

            $script:Fixture.Groups.Add([PSCustomObject]@{ id = 'g-stray'; displayName = 'ZZ-TEST-Stray' })

            $result = Test-EntraEnvironment -Quiet
            $result.Passed | Should-BeFalse

            @(($result.Checks | Where-Object { $_.Name -eq 'Users' }).Missing) | Should-BeCollection @('ZZ-TEST-awhitfield@lab.example.com')
            $names = $result.Checks | Where-Object { $_.Name -eq 'User display names' }
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^jnino:'
            @(($result.Checks | Where-Object { $_.Name -eq 'Groups' }).Unexpected) | Should-BeCollection @('ZZ-TEST-Stray')
        }
    }

    It 'names a membership the data lists and the tenant lacks, and forgives one it never listed' {
        InModuleScope TestEnvironment {
            $groupId = @($script:MembersByGroupId.Keys | Where-Object { $script:MembersByGroupId[$_].Count -gt 1 } | Sort-Object)[0]
            $dropped = $script:MembersByGroupId[$groupId][0]
            $null = $script:MembersByGroupId[$groupId].Remove($dropped)
            $script:MembersByGroupId[$groupId].Add([PSCustomObject]@{ id = 'u-extra'; userPrincipalName = 'ZZ-TEST-extra@lab.example.com'; displayName = 'Extra' })
            $groupName = ($script:Fixture.Groups | Where-Object { $_.id -eq $groupId }).displayName
            $droppedName = if ($dropped.userPrincipalName) { $dropped.userPrincipalName } else { $dropped.displayName }

            $check = (Test-EntraEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('{0} <- {1}' -f $groupName, $droppedName)
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'does not ask for role eligibilities when the connect read that the tenant has no P2, and counts them as none' {
        InModuleScope TestEnvironment {
            Mock Get-EntraConnection { @{ TenantId = 'tenant-1'; UpnSuffix = 'lab.example.com'; Capabilities = [PSCustomObject]@{ Known = $true; EntraP1 = $false; EntraP2 = $false } } }
            $result = Test-EntraEnvironment -SkipMembership -Quiet -WarningVariable warnings -WarningAction SilentlyContinue
            Should-NotInvoke Get-EntraSeededObject -ParameterFilter { $Type -eq 'RoleEligibilities' }
            ($result.Checks | Where-Object { $_.Name -eq 'RoleEligibilities' }).Found | Should-Be 0
            @($warnings) | Should-BeCollection -Count 0
        }
    }

    It 'sends no batch under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-EntraEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Invoke-EntraBatch
            Should-NotInvoke Write-TestMessage
        }
    }
}
