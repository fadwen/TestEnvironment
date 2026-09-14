#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the realm when a name came back wrong. So the realm here is built
    from the module's own seed files by the rules the seed applies - a user's uid is its row's
    username with no prefix, every invented name goes through Resolve-FreeIPASeedName, users split
    by lifecycle into active, staged and preserved, every attribute a list - and the verifier must
    pass against it. The first live run caught exactly this: a verifier that prefixed the uids
    reported every one of 355 users missing and 355 unexpected against a realm seeded correctly. Then one user is removed, one display
    name is swapped for its decomposed twin that -eq calls equal, one group is added that the data
    never names, and one membership is dropped, and every one of those must be named in the result.

    Everything is mocked. The realm is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\FreeIPA\Data'
}

Describe 'Test-FreeIPAEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; AuthType = 'ServiceAccount' } }
            Mock Get-FreeIPASeedMarker {
                [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; NamePrefix = 'zz-test-'; Tag = 'ZZ-TEST-seed'; Marker = '[ZZ-TEST-seed]'; Attribute = 'userclass' }
            }
            # The naming rule, as one deterministic function the fixture and the verifier share.
            Mock Resolve-FreeIPASeedName {
                if ($Kind -eq 'Host') { return 'zz-test-{0}.zz-test-lab.ipa.example.com' -f $Key.ToLowerInvariant() }
                'zz-test-{0}' -f $Key.ToLowerInvariant()
            }

            $userRows = @(Import-Csv -Path (Join-Path $DataPath 'FreeIPAUsers.csv') -Encoding UTF8)
            $groupRows = @(Import-Csv -Path (Join-Path $DataPath 'FreeIPAGroups.csv') -Encoding UTF8)
            $hostRows = @(Import-Csv -Path (Join-Path $DataPath 'FreeIPAHosts.csv') -Encoding UTF8)
            $user = {
                param($row)
                [PSCustomObject]@{
                    uid            = @($row.Username)
                    displayname    = @($row.DisplayName)
                    userclass      = @('ZZ-TEST-seed', $row.Class)
                    memberof_group = @($row.Groups -split ';' | Where-Object { $_ } | ForEach-Object { 'zz-test-{0}' -f $_.ToLowerInvariant() })
                }
            }

            $script:Fixture = @{
                Users          = [System.Collections.Generic.List[object]]@($userRows | Where-Object { $_.Lifecycle -notin 'Staged', 'Preserved' } | ForEach-Object { & $user $_ })
                StagedUsers    = @($userRows | Where-Object { $_.Lifecycle -eq 'Staged' } | ForEach-Object { & $user $_ })
                PreservedUsers = @($userRows | Where-Object { $_.Lifecycle -eq 'Preserved' } | ForEach-Object { & $user $_ })
                Groups         = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object {
                        [PSCustomObject]@{ cn = @('zz-test-{0}' -f $_.Name.ToLowerInvariant()); description = @('x [ZZ-TEST-seed]') }
                    })
                Hosts          = @($hostRows | ForEach-Object {
                        [PSCustomObject]@{
                            fqdn               = @('zz-test-{0}.zz-test-lab.ipa.example.com' -f $_.Name.ToLowerInvariant())
                            memberof_hostgroup = @($_.Hostgroups -split ';' | Where-Object { $_ } | ForEach-Object { 'zz-test-{0}' -f $_.ToLowerInvariant() })
                        }
                    })
                HbacRules      = @([PSCustomObject]@{ cn = @('zz-test-finance-payroll') })
            }
            $script:ActiveRows = @($userRows | Where-Object { $_.Lifecycle -notin 'Staged', 'Preserved' })
            $script:StagedRows = @($userRows | Where-Object { $_.Lifecycle -eq 'Staged' })

            Mock Get-FreeIPASeededObject {
                if ($script:Fixture.ContainsKey($Type)) { return @($script:Fixture[$Type]) }
                @()
            }
            Mock Invoke-FreeIPARequest { throw "Unexpected request $Method" }
        }
    }

    It 'passes against a realm that holds exactly what the data describes, by lifecycle, and counts the rest' {
        InModuleScope TestEnvironment {
            $result = Test-FreeIPAEnvironment -Quiet

            $result.Provider | Should-Be 'FreeIPA'
            $result.Target | Should-Be 'https://ipa.example.com'
            $result.Passed | Should-BeTrue
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            ($result.Checks | Where-Object { $_.Name -eq 'Users' }).Expected | Should-Be $script:ActiveRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Staged users' }).Expected | Should-Be $script:StagedRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Hostgroup memberships' }).Passed | Should-BeTrue

            $rules = $result.Checks | Where-Object { $_.Name -eq 'HbacRules' }
            $rules.Found | Should-Be 1
            $rules.Passed | Should-BeNull

            # The detail read is what carries display names and memberships.
            Should-Invoke Get-FreeIPASeededObject -Times 1 -Exactly -ParameterFilter { $Type -eq 'Users' -and $Detail }
            Should-Invoke Get-FreeIPASeededObject -Times 1 -Exactly -ParameterFilter { $Type -eq 'Hosts' -and $Detail }
        }
    }

    It 'names a missing user, a name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            $gone = $script:Fixture.Users | Where-Object { $_.uid[0] -eq 'awhitfield' }
            $null = $script:Fixture.Users.Remove($gone)

            $jose = $script:Fixture.Users | Where-Object { $_.uid[0] -eq 'jnino' }
            $decomposed = 'Jose' + [string][char]0x0301 + ' Nin' + [string][char]0x0303 + 'o'
            ($decomposed -eq $jose.displayname[0]) | Should-BeTrue
            $jose.displayname = @($decomposed)

            $script:Fixture.Groups.Add([PSCustomObject]@{ cn = @('zz-test-stray'); description = @('x [ZZ-TEST-seed]') })

            $result = Test-FreeIPAEnvironment -Quiet
            $result.Passed | Should-BeFalse

            @(($result.Checks | Where-Object { $_.Name -eq 'Users' }).Missing) | Should-BeCollection @('awhitfield')
            $names = $result.Checks | Where-Object { $_.Name -eq 'User display names' }
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^jnino:'
            @(($result.Checks | Where-Object { $_.Name -eq 'Groups' }).Unexpected) | Should-BeCollection @('zz-test-stray')
        }
    }

    It 'names a membership the data lists and the realm lacks, and forgives one an automember rule added' {
        InModuleScope TestEnvironment {
            $user = @($script:Fixture.Users | Where-Object { @($_.memberof_group).Count -gt 1 } | Sort-Object { $_.uid[0] })[0]
            $dropped = $user.memberof_group[0]
            $user.memberof_group = @($user.memberof_group | Select-Object -Skip 1) + @('zz-test-automember-added')

            $check = (Test-FreeIPAEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('{0} <- {1}' -f $dropped, $user.uid[0])
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'compares no memberships under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-FreeIPAEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -like '*memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Write-TestMessage
        }
    }
}
