#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the environment when a name came back wrong. So the environment
    here is built from the module's own seed files by the rules the seed applies - every name
    through Resolve-PingOneSeedName, given and family names on the user, memberships behind
    users/{id}/memberOfGroups - and the verifier must pass against it. Then one user is removed,
    one given name is swapped for its decomposed twin that -eq calls equal, one group is added that
    the data never names, and one membership is dropped, and every one of those must be named in
    the result. The decomposed name is the case that matters most here: the PingOne provider once
    stored every accented name as U+FFFD and the service accepted every request.

    Everything is mocked. The environment is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\PingOne\Data'
}

Describe 'Test-PingOneEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-PingOneConnection { @{ EnvironmentId = 'env-1'; AuthEnvironmentId = 'env-0'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com' } }
            # The naming rule, as one deterministic function the fixture and the verifier share.
            Mock Resolve-PingOneSeedName {
                switch ($Kind) {
                    'Username' { ('ZZ-TEST-{0}' -f $Key).ToLowerInvariant() }
                    'Email' { ('ZZ-TEST-{0}@lab.example.com' -f $Key).ToLowerInvariant() }
                    default { 'ZZ-TEST-{0}' -f $Key }
                }
            }

            $data = $DataPath
            $read = { param($file) @(Import-Csv -LiteralPath (Join-Path $data $file) -Encoding UTF8) }
            $populationRows = & $read 'PingOnePopulations.csv'
            $userRows = & $read 'PingOneUsers.csv'
            $groupRows = & $read 'PingOneGroups.csv'
            $applicationRows = & $read 'PingOneApplications.csv'
            $resourceRows = & $read 'PingOneResources.csv'
            $attributeRows = & $read 'PingOneProfileAttributes.csv'

            $groupNameByKey = @{}
            foreach ($row in $groupRows) { $groupNameByKey[$row.Key] = 'ZZ-TEST-{0}' -f $row.Name }

            $script:Fixture = @{
                Populations  = @($populationRows | ForEach-Object { [PSCustomObject]@{ id = "p-$($_.Key)"; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Users        = [System.Collections.Generic.List[object]]@($userRows | ForEach-Object {
                        [PSCustomObject]@{ id = "u-$($_.Key)"; username = ('ZZ-TEST-{0}' -f $_.Key).ToLowerInvariant(); name = [PSCustomObject]@{ given = $_.GivenName; family = $_.FamilyName } }
                    })
                Groups       = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object { [PSCustomObject]@{ id = "g-$($_.Key)"; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Applications = @($applicationRows | ForEach-Object { [PSCustomObject]@{ id = "a-$($_.Key)"; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Resources    = @($resourceRows | ForEach-Object { [PSCustomObject]@{ id = "r-$($_.Key)"; name = 'ZZ-TEST-{0}' -f $_.Name } })
                Attributes   = @($attributeRows | ForEach-Object { [PSCustomObject]@{ id = "at-$($_.Name)"; name = $_.Name } })
            }
            $script:MembershipsByUserId = @{}
            foreach ($row in $userRows) {
                $script:MembershipsByUserId["u-$($row.Key)"] = [System.Collections.Generic.List[object]]@($row.Groups -split ';' | Where-Object { $_ } | ForEach-Object {
                        [PSCustomObject]@{ id = "g-$_"; name = $groupNameByKey[$_]; type = 'DIRECT' }
                    })
            }
            $script:UserRows = $userRows
            $script:ExpectedPairs = @($userRows | ForEach-Object { @($_.Groups -split ';' | Where-Object { $_ }) }).Count
            $script:UsersWithGroups = @($userRows | Where-Object { $_.Groups }).Count

            Mock Get-PingOneSeededObject { @($script:Fixture[$Type]) }
            Mock Invoke-PingOneRequest {
                if ($Method -eq 'GET' -and $Path -match '^users/(.+)/memberOfGroups$') { return $script:MembershipsByUserId[$matches[1]].ToArray() }
                throw "Unexpected request $Method $Path"
            }
        }
    }

    It 'passes against an environment that holds exactly what the data describes, reading memberships once per user that has any' {
        InModuleScope TestEnvironment {
            $result = Test-PingOneEnvironment -Quiet

            $result.Provider | Should-Be 'PingOne'
            $result.Target | Should-Be 'env-1'
            $result.Passed | Should-BeTrue
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            ($result.Checks | Where-Object { $_.Name -eq 'Users' }).Expected | Should-Be $script:UserRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }).Expected | Should-Be $script:ExpectedPairs
            $attributes = $result.Checks | Where-Object { $_.Name -eq 'Attributes' }
            $attributes.Kind | Should-Be 'Count'
            $attributes.Passed | Should-BeTrue

            Should-Invoke Invoke-PingOneRequest -Times $script:UsersWithGroups -Exactly -ParameterFilter { $Path -like 'users/*/memberOfGroups' }
        }
    }

    It 'names a missing user, a given name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            $gone = $script:Fixture.Users | Where-Object { $_.username -eq 'zz-test-awhitfield' }
            $null = $script:Fixture.Users.Remove($gone)

            $jose = $script:Fixture.Users | Where-Object { $_.username -eq 'zz-test-jnino' }
            $decomposed = 'Jose' + [string][char]0x0301
            ($decomposed -eq $jose.name.given) | Should-BeTrue
            $jose.name.given = $decomposed

            $script:Fixture.Groups.Add([PSCustomObject]@{ id = 'g-stray'; name = 'ZZ-TEST-Stray' })

            $result = Test-PingOneEnvironment -Quiet
            $result.Passed | Should-BeFalse

            @(($result.Checks | Where-Object { $_.Name -eq 'Users' }).Missing) | Should-BeCollection @('zz-test-awhitfield')
            $names = $result.Checks | Where-Object { $_.Name -eq 'User names' }
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^jnino: given name'
            @(($result.Checks | Where-Object { $_.Name -eq 'Groups' }).Unexpected) | Should-BeCollection @('ZZ-TEST-Stray')
        }
    }

    It 'names a membership the data lists and the environment lacks, and forgives one a filter added' {
        InModuleScope TestEnvironment {
            $userId = @($script:MembershipsByUserId.Keys | Where-Object { $script:MembershipsByUserId[$_].Count -gt 1 } | Sort-Object)[0]
            $dropped = $script:MembershipsByUserId[$userId][0]
            $null = $script:MembershipsByUserId[$userId].Remove($dropped)
            $script:MembershipsByUserId[$userId].Add([PSCustomObject]@{ id = 'g-dynamic'; name = 'ZZ-TEST-Dynamic'; type = 'INDIRECT' })
            $username = ($script:Fixture.Users | Where-Object { $_.id -eq $userId }).username

            $check = (Test-PingOneEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('{0} <- {1}' -f $dropped.name, $username)
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'reads no memberships under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-PingOneEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Invoke-PingOneRequest
            Should-NotInvoke Write-TestMessage
        }
    }
}
