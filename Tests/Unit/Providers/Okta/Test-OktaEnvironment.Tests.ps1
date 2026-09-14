#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the directory when a name came back wrong. So the org here is built
    from the module's own seed files by the rules New-OktaUser, New-OktaGroup and New-OktaApp
    apply - login from LoginPrefix and the email domain, names and labels behind the prefix - and
    the verifier must pass against it. Then one user is removed, one name is swapped for its
    decomposed twin that -eq calls equal, one group is added that the data never names, and one
    membership is dropped, and every one of those must be named in the result.

    Everything is mocked. The org is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\Okta\Data'
}

Describe 'Test-OktaEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-OktaConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'; EmailDomain = 'oktalab.example.com'; SeedMarker = '[ZZ-TEST-seed]'; SeedTag = 'ZZ-TEST-seed' }
            }

            $userRows = @(Import-Csv -Path (Join-Path $DataPath 'OktaUsers.csv') -Encoding UTF8)
            $groupRows = @(Import-Csv -Path (Join-Path $DataPath 'OktaGroups.csv') -Encoding UTF8)
            $appRows = @(Import-Csv -Path (Join-Path $DataPath 'OktaApps.csv') -Encoding UTF8)

            # The org as the seed builds it.
            $script:Users = [System.Collections.Generic.List[object]]@($userRows | ForEach-Object {
                    [PSCustomObject]@{ id = "u-$($_.LoginPrefix)"; profile = [PSCustomObject]@{ login = '{0}@oktalab.example.com' -f $_.LoginPrefix; displayName = $_.DisplayName } }
                })
            $script:Groups = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object {
                    [PSCustomObject]@{ id = "g-$($_.Name)"; profile = [PSCustomObject]@{ name = 'OKTALAB-{0}' -f $_.DisplayName; description = 'x [ZZ-TEST-seed]' } }
                })
            $script:Apps = @($appRows | ForEach-Object { [PSCustomObject]@{ id = "a-$($_.Name)"; label = 'OKTALAB-{0}' -f $_.Label } })
            $script:MembersByGroupId = @{}
            foreach ($row in $groupRows) {
                $script:MembersByGroupId["g-$($row.Name)"] = [System.Collections.Generic.List[object]]@($row.Members -split ';' | Where-Object { $_ } | ForEach-Object {
                        [PSCustomObject]@{ id = "u-$_"; profile = [PSCustomObject]@{ login = '{0}@oktalab.example.com' -f $_ } }
                    })
            }
            $script:ExpectedPairs = @($groupRows | ForEach-Object { @($_.Members -split ';' | Where-Object { $_ }) }).Count
            $script:UserRows = $userRows

            Mock Get-OktaSeededUser { $script:Users.ToArray() }
            Mock Get-OktaSeededGroup { $script:Groups.ToArray() }
            Mock Get-OktaSeededApp { $script:Apps }
            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -match '^/api/v1/groups/(.+)/users$') { return $script:MembersByGroupId[$matches[1]].ToArray() }
                throw "Unexpected request $Method $Path"
            }
        }
    }

    It 'passes against an org that holds exactly what the data describes, finding objects the way teardown does' {
        InModuleScope TestEnvironment {
            $result = Test-OktaEnvironment -Quiet

            $result.Provider | Should-Be 'Okta'
            $result.Target | Should-Be 'https://trial-1.okta.com'
            $result.Passed | Should-BeTrue
            $result.Failed | Should-Be 0
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            $users = $result.Checks | Where-Object { $_.Name -eq 'Users' }
            $users.Expected | Should-Be $script:UserRows.Count
            $users.Found | Should-Be $script:UserRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }).Expected | Should-Be $script:ExpectedPairs

            Should-Invoke Get-OktaSeededUser -Times 1 -Exactly -ParameterFilter { $Prefix -eq 'OKTALAB' -and $EmailDomain -eq 'oktalab.example.com' }
            Should-Invoke Get-OktaSeededGroup -Times 1 -Exactly -ParameterFilter { $SeedMarker -eq '[ZZ-TEST-seed]' }
        }
    }

    It 'names a missing user, a name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            $gone = $script:Users | Where-Object { $_.profile.login -eq 'awhitfield@oktalab.example.com' }
            $null = $script:Users.Remove($gone)

            # The same name to -eq, and to the eye; a different string on the wire.
            $jose = $script:Users | Where-Object { $_.profile.login -eq 'jnino@oktalab.example.com' }
            $decomposed = 'Jose' + [string][char]0x0301 + ' Nin' + [string][char]0x0303 + 'o'
            ($decomposed -eq $jose.profile.displayName) | Should-BeTrue
            $jose.profile.displayName = $decomposed

            $script:Groups.Add([PSCustomObject]@{ id = 'g-stray'; profile = [PSCustomObject]@{ name = 'OKTALAB-Stray'; description = 'x [ZZ-TEST-seed]' } })

            $result = Test-OktaEnvironment -Quiet
            $result.Passed | Should-BeFalse
            $result.Failed | Should-Be 3

            $users = $result.Checks | Where-Object { $_.Name -eq 'Users' }
            @($users.Missing) | Should-BeCollection @('awhitfield@oktalab.example.com')
            @($users.Unexpected) | Should-BeCollection -Count 0

            $names = $result.Checks | Where-Object { $_.Name -eq 'User display names' }
            $names.Passed | Should-BeFalse
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^jnino:'

            $groups = $result.Checks | Where-Object { $_.Name -eq 'Groups' }
            @($groups.Unexpected) | Should-BeCollection @('OKTALAB-Stray')
        }
    }

    It 'names a membership the data lists and the org lacks, and forgives one a rule added' {
        InModuleScope TestEnvironment {
            $groupId = @($script:MembersByGroupId.Keys | Where-Object { $script:MembersByGroupId[$_].Count -gt 0 } | Sort-Object)[0]
            $dropped = $script:MembersByGroupId[$groupId][0]
            $null = $script:MembersByGroupId[$groupId].Remove($dropped)
            $script:MembersByGroupId[$groupId].Add([PSCustomObject]@{ id = 'u-rule'; profile = [PSCustomObject]@{ login = 'rule-added@oktalab.example.com' } })
            $groupName = ($script:Groups | Where-Object { $_.id -eq $groupId }).profile.name

            $check = (Test-OktaEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('{0} <- {1}' -f $groupName, $dropped.profile.login)
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'reads no memberships under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-OktaEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Invoke-OktaRequest
            Should-NotInvoke Write-TestMessage

            $null = Test-OktaEnvironment -SkipMembership
            Should-Invoke Write-TestMessage -ParameterFilter { $Type -eq 'Header' }
        }
    }
}
