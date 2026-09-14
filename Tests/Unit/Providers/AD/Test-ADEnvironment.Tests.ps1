#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the directory when a name came back wrong. So the domain here is
    built from the module's own seed files by the rules the seed applies - accounts by
    SamAccountName, computers and groups behind the prefix, every object under its OU with the tag
    in adminDescription - and the verifier must pass against it. Then one user is removed, one
    display name is swapped for its decomposed twin that -eq calls equal, one group is added that
    the data never names, and one rule-defined membership is dropped, and every one of those must
    be named in the result.

    Two things are specific to AD. Membership is a rule, so the expectation is what
    Resolve-ADTestGroupMember says over the seeded directory, and the same resolver is mocked here
    so the test is about the comparison rather than the rule. And a search base that does not exist
    is an error to the AD cmdlets, so when the seed OU is gone the verifier must report everything
    missing without searching.

    Everything is mocked. The directory is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\AD\Data'
}

Describe 'Test-ADEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com'; ForestDN = 'DC=contoso,DC=com' } }
            Mock Get-ADTestSeedMarker { [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; Tag = 'ZZ-TEST-seed'; Description = 'ZZ-TEST-seed' } }
            Mock Get-ADOrganizationalUnit { @([PSCustomObject]@{ Name = 'ZZ-TEST-TestData'; DistinguishedName = 'OU=ZZ-TEST-TestData,DC=contoso,DC=com' }) }

            $seedRoot = 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
            $data = $DataPath
            $read = { param($file) @(Import-Csv -LiteralPath (Join-Path $data $file) -Encoding UTF8) }
            $userRows = & $read 'ADUsers.csv'
            $serviceRows = & $read 'ADServiceAccounts.csv'
            $deviceRows = & $read 'ADDevices.csv'
            $groupRows = & $read 'ADSecurityGroups.csv'

            $script:Users = [System.Collections.Generic.List[object]]@($userRows | ForEach-Object {
                    [PSCustomObject]@{ SamAccountName = $_.SamAccountName; DisplayName = $_.Name; DistinguishedName = "CN=$($_.Name),OU=$($_.Department),OU=Users,$seedRoot"; adminDescription = 'ZZ-TEST-seed' }
                })
            $script:ServiceAccounts = @($serviceRows | ForEach-Object {
                    [PSCustomObject]@{ SamAccountName = $_.SamAccountName; DisplayName = $_.Name; DistinguishedName = "CN=$($_.Name),OU=ServiceAccounts,$seedRoot"; adminDescription = 'ZZ-TEST-seed' }
                })
            $script:Computers = @($deviceRows | ForEach-Object {
                    [PSCustomObject]@{ Name = 'ZZ-TEST-{0}' -f $_.DeviceName; DistinguishedName = "CN=ZZ-TEST-$($_.DeviceName),OU=Devices,$seedRoot"; adminDescription = 'ZZ-TEST-seed' }
                })
            $script:Groups = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object {
                    [PSCustomObject]@{ Name = 'ZZ-TEST-{0}' -f $_.GroupName; DistinguishedName = "CN=ZZ-TEST-$($_.GroupName),OU=Groups,$seedRoot"; adminDescription = 'ZZ-TEST-seed' }
                })

            # What each rule resolves to: two seeded users, chosen by the group so the sets differ.
            $script:RuleMembers = @{}
            $script:MembersByDn = @{}
            $ruleRows = @($groupRows | Where-Object { $_.MemberFilter })
            $i = 0
            foreach ($row in $ruleRows) {
                $picked = @($script:Users[($i % $script:Users.Count)], $script:Users[(($i + 7) % $script:Users.Count)])
                $i++
                $script:RuleMembers[$row.GroupName] = $picked
                $script:MembersByDn["CN=ZZ-TEST-$($row.GroupName),OU=Groups,$seedRoot"] = [System.Collections.Generic.List[object]]@($picked | ForEach-Object { [PSCustomObject]@{ DistinguishedName = $_.DistinguishedName } })
            }
            # Nesting: the child sits in each parent its row names.
            foreach ($row in ($groupRows | Where-Object { $_.MemberOfGroup })) {
                foreach ($parentName in @($row.MemberOfGroup -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                    $parentDn = "CN=ZZ-TEST-$parentName,OU=Groups,$seedRoot"
                    if (-not $script:MembersByDn.ContainsKey($parentDn)) { $script:MembersByDn[$parentDn] = New-Object System.Collections.Generic.List[object] }
                    $script:MembersByDn[$parentDn].Add([PSCustomObject]@{ DistinguishedName = "CN=ZZ-TEST-$($row.GroupName),OU=Groups,$seedRoot" })
                }
            }
            $script:UserRows = $userRows
            $script:RuleRows = $ruleRows
            $script:ExpectedPairs = (2 * $ruleRows.Count) + @($groupRows | ForEach-Object { @($_.MemberOfGroup -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }).Count

            Mock Get-ADUser {
                if ($SearchBase -like 'OU=Users,*') { return $script:Users.ToArray() }
                if ($SearchBase -like 'OU=ServiceAccounts,*') { return $script:ServiceAccounts }
                @()
            }
            Mock Get-ADComputer { $script:Computers }
            Mock Get-ADGroup { $script:Groups.ToArray() }
            Mock Resolve-ADTestGroupMember { if ($script:RuleMembers.ContainsKey($Rule.GroupName)) { $script:RuleMembers[$Rule.GroupName] } }
            Mock Get-ADGroupMember { if ($script:MembersByDn.ContainsKey($Identity)) { $script:MembersByDn[$Identity].ToArray() } else { @() } }
        }
    }

    It 'passes against a domain that holds exactly what the data describes, searching only under the seed OU' {
        InModuleScope TestEnvironment {
            $result = Test-ADEnvironment -Quiet

            $result.Provider | Should-Be 'AD'
            $result.Target | Should-Be 'contoso.com'
            $result.Passed | Should-BeTrue
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            ($result.Checks | Where-Object { $_.Name -eq 'Users' }).Expected | Should-Be $script:UserRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }).Expected | Should-Be $script:ExpectedPairs

            Should-Invoke Get-ADUser -Times 2 -Exactly -ParameterFilter { $SearchBase -like '*,OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            Should-Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Devices,OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            Should-Invoke Get-ADGroup -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            Should-Invoke Resolve-ADTestGroupMember -ParameterFilter { $SeedRoot -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
        }
    }

    It 'leaves an object inside the seed OU alone when it does not carry the tag, and reports it unexpected to nobody' {
        InModuleScope TestEnvironment {
            # Not the module's: it is inside the container but not tagged, so ownership discovery
            # skips it the same way teardown would, and it is neither present nor unexpected.
            $script:Groups.Add([PSCustomObject]@{ Name = 'ZZ-TEST-Not Ours'; DistinguishedName = 'CN=ZZ-TEST-Not Ours,OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com'; adminDescription = $null })
            $groups = (Test-ADEnvironment -SkipMembership -Quiet -WarningAction SilentlyContinue).Checks | Where-Object { $_.Name -eq 'Groups' }
            $groups.Passed | Should-BeTrue
            @($groups.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'names a missing user, a name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            # The AD data logs its people in as first name plus initial, so the same two people
            # carry different logins here than in every other provider.
            $gone = $script:Users | Where-Object { $_.SamAccountName -eq 'danj' }
            $null = $script:Users.Remove($gone)

            $jose = $script:Users | Where-Object { $_.SamAccountName -eq 'josen' }
            $decomposed = 'Jose' + [string][char]0x0301 + ' Nin' + [string][char]0x0303 + 'o'
            ($decomposed -eq $jose.DisplayName) | Should-BeTrue
            $jose.DisplayName = $decomposed

            $script:Groups.Add([PSCustomObject]@{ Name = 'ZZ-TEST-Stray'; DistinguishedName = 'CN=ZZ-TEST-Stray,OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })

            $result = Test-ADEnvironment -Quiet
            $result.Passed | Should-BeFalse

            @(($result.Checks | Where-Object { $_.Name -eq 'Users' }).Missing) | Should-BeCollection @('danj')
            $names = $result.Checks | Where-Object { $_.Name -eq 'User display names' }
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^josen:'
            @(($result.Checks | Where-Object { $_.Name -eq 'Groups' }).Unexpected) | Should-BeCollection @('ZZ-TEST-Stray')
        }
    }

    It 'names a rule-defined membership the group lacks, and forgives a member the rule never named' {
        InModuleScope TestEnvironment {
            $row = $script:RuleRows[0]
            $dn = "CN=ZZ-TEST-$($row.GroupName),OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com"
            $dropped = $script:MembersByDn[$dn][0]
            $null = $script:MembersByDn[$dn].Remove($dropped)
            $script:MembersByDn[$dn].Add([PSCustomObject]@{ DistinguishedName = 'CN=By Hand,OU=Sales,OU=Users,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })

            $check = (Test-ADEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('ZZ-TEST-{0} <- {1}' -f $row.GroupName, $dropped.DistinguishedName)
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'reports everything missing and searches nothing when the seed OU is gone' {
        InModuleScope TestEnvironment {
            Mock Get-ADOrganizationalUnit { @() }
            $result = Test-ADEnvironment -Quiet -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Passed | Should-BeFalse
            $users = $result.Checks | Where-Object { $_.Name -eq 'Users' }
            $users.Found | Should-Be 0
            @($users.Missing).Count | Should-Be $script:UserRows.Count
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            @($warnings | Where-Object { $_ -like '*does not exist*' }).Count | Should-Be 1
            Should-NotInvoke Get-ADUser
            Should-NotInvoke Get-ADGroupMember
        }
    }

    It 'reads no memberships under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-ADEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Get-ADGroupMember
            Should-NotInvoke Resolve-ADTestGroupMember
            Should-NotInvoke Write-TestMessage
        }
    }
}
