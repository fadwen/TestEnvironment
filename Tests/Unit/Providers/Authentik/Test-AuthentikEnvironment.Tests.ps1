#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Verification is only worth having if it agrees with the seed about what a seeded object is
    called, and disagrees with the instance when a name came back wrong. So the instance here is
    built from the module's own seed files by the rules New-AuthentikUser, New-AuthentikGroup and
    New-AuthentikApplication apply - an unprefixed username under the seed path, a group and an
    application behind the prefix, memberships as group primary keys on the user - and the verifier
    must pass against it. Then one user is removed, one name is swapped for its decomposed twin
    that -eq calls equal, one group is added that the data never names, and one membership is
    dropped, and every one of those must be named in the result.

    Everything is mocked. The instance is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:DataPath = Join-Path $moduleRoot 'Providers\Authentik\Data'
}

Describe 'Test-AuthentikEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ DataPath = $script:DataPath } {
            param($DataPath)
            Mock Write-TestMessage { }
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com'; Prefix = 'ZZ-TEST-'; AuthType = 'ServiceAccount' } }
            Mock Get-AuthentikSeedMarker {
                [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; SlugPrefix = 'zz-test-'; UserPath = 'zz-test'; Tag = 'ZZ-TEST-seed'; Marker = '[ZZ-TEST-seed]'; Attribute = 'labSeedTag' }
            }

            $userRows = @(Import-Csv -Path (Join-Path $DataPath 'AuthentikUsers.csv') -Encoding UTF8)
            $groupRows = @(Import-Csv -Path (Join-Path $DataPath 'AuthentikGroups.csv') -Encoding UTF8)
            $applicationRows = @(Import-Csv -Path (Join-Path $DataPath 'AuthentikApplications.csv') -Encoding UTF8)

            # The instance as the seed builds it: a group's primary key is its row key here, which
            # is what a user row names in its Groups column.
            $script:Fixture = @{
                Users        = [System.Collections.Generic.List[object]]@($userRows | ForEach-Object {
                        [PSCustomObject]@{ pk = "u-$($_.Username)"; username = $_.Username; name = $_.Name; path = 'zz-test'; groups = @($_.Groups -split ';' | Where-Object { $_ }) }
                    })
                Groups       = [System.Collections.Generic.List[object]]@($groupRows | ForEach-Object {
                        [PSCustomObject]@{ pk = $_.Name; name = 'ZZ-TEST-{0}' -f $_.DisplayName }
                    })
                Applications = @($applicationRows | ForEach-Object { [PSCustomObject]@{ pk = "a-$($_.Name)"; name = 'ZZ-TEST-{0}' -f $_.Name; slug = $_.Slug } })
                Flows        = @([PSCustomObject]@{ pk = 'f-1'; name = 'ZZ-TEST-Sign in' }, [PSCustomObject]@{ pk = 'f-2'; name = 'ZZ-TEST-Enrol' })
            }
            $script:UserRows = $userRows
            $script:ExpectedPairs = @($userRows | ForEach-Object { @($_.Groups -split ';' | Where-Object { $_ }) }).Count

            Mock Get-AuthentikSeededObject {
                if ($script:Fixture.ContainsKey($Type)) { return @($script:Fixture[$Type]) }
                @()
            }
            Mock Invoke-AuthentikRequest { throw "Unexpected request $Method $Path" }
        }
    }

    It 'passes against an instance that holds exactly what the data describes, and counts the rest' {
        InModuleScope TestEnvironment {
            $result = Test-AuthentikEnvironment -Quiet

            $result.Provider | Should-Be 'Authentik'
            $result.Target | Should-Be 'https://auth.example.com'
            $result.Passed | Should-BeTrue
            @($result.Checks | Where-Object { $_.Passed -eq $false }) | Should-BeCollection -Count 0

            ($result.Checks | Where-Object { $_.Name -eq 'Users' }).Expected | Should-Be $script:UserRows.Count
            ($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }).Expected | Should-Be $script:ExpectedPairs

            $flows = $result.Checks | Where-Object { $_.Name -eq 'Flows' }
            $flows.Kind | Should-Be 'Count'
            $flows.Found | Should-Be 2
            $flows.Passed | Should-BeNull
            @($result.Checks | Where-Object { $_.Name -eq 'Tokens' }).Count | Should-Be 1
        }
    }

    It 'names a missing user, a name that came back decomposed, and a group the data never describes' {
        InModuleScope TestEnvironment {
            $gone = $script:Fixture.Users | Where-Object { $_.username -eq 'awhitfield' }
            $null = $script:Fixture.Users.Remove($gone)

            $jose = $script:Fixture.Users | Where-Object { $_.username -eq 'jnino' }
            $decomposed = 'Jose' + [string][char]0x0301 + ' Nin' + [string][char]0x0303 + 'o'
            ($decomposed -eq $jose.name) | Should-BeTrue
            $jose.name = $decomposed

            $script:Fixture.Groups.Add([PSCustomObject]@{ pk = 'stray'; name = 'ZZ-TEST-Stray' })

            $result = Test-AuthentikEnvironment -Quiet
            $result.Passed | Should-BeFalse

            @(($result.Checks | Where-Object { $_.Name -eq 'Users' }).Missing) | Should-BeCollection @('awhitfield')
            $names = $result.Checks | Where-Object { $_.Name -eq 'User names' }
            @($names.Missing).Count | Should-Be 1
            $names.Missing[0] | Should-MatchString '^jnino:'
            @(($result.Checks | Where-Object { $_.Name -eq 'Groups' }).Unexpected) | Should-BeCollection @('ZZ-TEST-Stray')
        }
    }

    It 'names a membership the data lists and the instance lacks, and forgives one it never listed' {
        InModuleScope TestEnvironment {
            $user = @($script:Fixture.Users | Where-Object { @($_.groups).Count -gt 1 } | Sort-Object username)[0]
            $droppedKey = $user.groups[0]
            $user.groups = @($user.groups | Select-Object -Skip 1) + @('stray')
            $script:Fixture.Groups.Add([PSCustomObject]@{ pk = 'stray'; name = 'ZZ-TEST-Stray' })
            $droppedName = ($script:Fixture.Groups | Where-Object { $_.pk -eq $droppedKey }).name

            $check = (Test-AuthentikEnvironment -Quiet).Checks | Where-Object { $_.Name -eq 'Group memberships' }
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @('{0} <- {1}' -f $droppedName, $user.username)
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'compares no memberships under -SkipMembership and prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $result = Test-AuthentikEnvironment -SkipMembership -Quiet
            @($result.Checks | Where-Object { $_.Name -eq 'Group memberships' }) | Should-BeCollection -Count 0
            Should-NotInvoke Write-TestMessage
        }
    }
}
