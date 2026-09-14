#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The comparison behind Compare-TestEnvironment, on identities alone. What has to hold: a
    person is matched by login key first and by display name among what is left, because the
    Active Directory data logs its people in as first name and initial and agrees with the
    others only on the names; what matches in neither way is reported as only on one side and is
    not a failure; matched names are compared by codepoint, so the decomposed José that -eq calls
    equal to the precomposed one is the finding; a display name is never compared against a name
    composed from parts, because that would call every family-name-first person a mismatch; and
    the enabled state is reported without a verdict.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'New-TestIdentity' -Tag 'Unit', 'Private' {

    It 'lower-cases the key, defaults it to the login, and keeps an absent name absent rather than empty' {
        InModuleScope TestEnvironment {
            $identity = New-TestIdentity -Provider 'Okta' -Login 'JNino@oktalab.example.com' -DisplayName '' -Enabled 'true'
            $identity.Key | Should-Be 'jnino@oktalab.example.com'
            $identity.Login | Should-Be 'JNino@oktalab.example.com'
            $identity.DisplayName | Should-BeNull
            $identity.GivenName | Should-BeNull
            $identity.Enabled | Should-BeTrue
            (New-TestIdentity -Provider 'AD' -Login 'josen' -Key 'JOSEN').Key | Should-Be 'josen'
            (New-TestIdentity -Provider 'AD' -Login 'josen').Enabled | Should-BeNull
        }
    }
}

Describe 'Compare-TestIdentitySnapshot' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Jose = 'Jos' + [string][char]0x00E9 + ' Ni' + [string][char]0x00F1 + 'o'
            $script:JoseDecomposed = 'Jose' + [string][char]0x0301 + ' Ni' + [string][char]0x00F1 + 'o'
            $script:Entra = [PSCustomObject]@{ Provider = 'Entra'; Target = 'tenant-1'; Identities = @(
                    New-TestIdentity -Provider Entra -Login 'ZZ-TEST-jnino@lab.example.com' -Key 'jnino' -DisplayName $script:Jose -Enabled $true
                    New-TestIdentity -Provider Entra -Login 'ZZ-TEST-danj@lab.example.com' -Key 'danj' -DisplayName 'Dan Jump' -Enabled $true
                    New-TestIdentity -Provider Entra -Login 'ZZ-TEST-mbell@lab.example.com' -Key 'mbell' -DisplayName 'Marcus Bell' -Enabled $false
                    New-TestIdentity -Provider Entra -Login 'ZZ-TEST-awhitfield@lab.example.com' -Key 'awhitfield' -DisplayName 'Ada Whitfield' -Enabled $true
                )
            }
            # The domain logs the same people in differently, and one of them came back decomposed.
            $script:AD = [PSCustomObject]@{ Provider = 'AD'; Target = 'contoso.com'; Identities = @(
                    New-TestIdentity -Provider AD -Login 'josen' -DisplayName $script:JoseDecomposed -GivenName 'Jose' -Surname 'Nino' -Enabled $true
                    New-TestIdentity -Provider AD -Login 'danj' -DisplayName 'Dan Jump' -Enabled $true
                    New-TestIdentity -Provider AD -Login 'marcusb' -DisplayName 'Marcus Bell' -Enabled $true
                    New-TestIdentity -Provider AD -Login 'zoem' -DisplayName ('Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller') -Enabled $true
                )
            }
        }
    }

    It 'matches by key, then by display name, and reports the rest as only on one side without failing for it' {
        InModuleScope TestEnvironment {
            $result = Compare-TestIdentitySnapshot -Left $script:Entra -Right $script:AD

            $result.Left.Provider | Should-Be 'Entra'
            $result.Left.Count | Should-Be 4
            $result.Right.Count | Should-Be 4
            $result.Matched | Should-Be 3
            $result.MatchedByKey | Should-Be 1
            $result.MatchedByName | Should-Be 2
            @($result.OnlyLeft) | Should-BeCollection @('awhitfield (Ada Whitfield)')
            @($result.OnlyRight) | Should-BeCollection @(('zoem (Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller)'))
        }
    }

    It 'compares matched names by codepoint, so the decomposed twin -eq calls equal is the finding, and it fails the comparison' {
        InModuleScope TestEnvironment {
            ($script:Jose -eq $script:JoseDecomposed) | Should-BeTrue
            $result = Compare-TestIdentitySnapshot -Left $script:Entra -Right $script:AD

            $result.NamesCompared | Should-Be 3
            @($result.NameMismatch).Count | Should-Be 1
            $result.NameMismatch[0] | Should-MatchString "^jnino: Entra has '"
            $result.Passed | Should-BeFalse
        }
    }

    It 'reports an enabled state that differs without a verdict' {
        InModuleScope TestEnvironment {
            $result = Compare-TestIdentitySnapshot -Left $script:Entra -Right $script:AD
            @($result.StateDifference) | Should-BeCollection @('mbell: disabled in Entra, enabled in AD')

            # The same people, agreeing on every name: the state alone does not fail it.
            $script:AD.Identities[0].DisplayName = $script:Jose
            (Compare-TestIdentitySnapshot -Left $script:Entra -Right $script:AD).Passed | Should-BeTrue
        }
    }

    It 'compares parts against parts when either side lacks a display name, and never a display name against a composed one' {
        InModuleScope TestEnvironment {
            # PingOne keeps given and family names and no display name; the Han name puts the
            # family name first, so composing one would call it a mismatch against every other provider.
            $pingOne = [PSCustomObject]@{ Provider = 'PingOne'; Target = 'env-1'; Identities = @(
                    New-TestIdentity -Provider PingOne -Login 'zz-test-hkobayashi' -Key 'hkobayashi' -GivenName ([string][char]0x82B1) -Surname ([string][char]0x5C0F + [string][char]0x6797) -Enabled $true
                    New-TestIdentity -Provider PingOne -Login 'zz-test-jnino' -Key 'jnino' -GivenName ('Jos' + [string][char]0xE9) -Surname ('Ni' + [string][char]0xF1 + 'o') -Enabled $true
                )
            }
            $entra = [PSCustomObject]@{ Provider = 'Entra'; Target = 't'; Identities = @(
                    New-TestIdentity -Provider Entra -Login 'x' -Key 'hkobayashi' -DisplayName ([string][char]0x5C0F + [string][char]0x6797 + ' ' + [string][char]0x82B1) -Enabled $true
                    New-TestIdentity -Provider Entra -Login 'y' -Key 'jnino' -DisplayName $script:Jose -Enabled $true
                )
            }
            $against = Compare-TestIdentitySnapshot -Left $entra -Right $pingOne
            $against.Matched | Should-Be 2
            $against.NamesCompared | Should-Be 0
            $against.Passed | Should-BeTrue

            $freeIpa = [PSCustomObject]@{ Provider = 'FreeIPA'; Target = 'realm'; Identities = @(
                    New-TestIdentity -Provider FreeIPA -Login 'jnino' -DisplayName $script:Jose -GivenName ('Jos' + [string][char]0xE9) -Surname 'Nino' -Enabled $true
                )
            }
            # FreeIPA keeps a display name and PingOne does not, so the parts both keep are compared,
            # by codepoint, and never FreeIPA's display name against a name composed from PingOne's.
            $parts = Compare-TestIdentitySnapshot -Left $freeIpa -Right $pingOne
            $parts.NamesCompared | Should-Be 1
            $parts.NameMismatch[0] | Should-MatchString "Ni" # Nino against Niño
            $parts.Passed | Should-BeFalse
        }
    }

    It 'passes two empty sides, with nothing matched and nothing compared' {
        InModuleScope TestEnvironment {
            $result = Compare-TestIdentitySnapshot -Left ([PSCustomObject]@{ Provider = 'A'; Target = 'a'; Identities = @() }) -Right ([PSCustomObject]@{ Provider = 'B'; Target = 'b'; Identities = @() })
            $result.Matched | Should-Be 0
            $result.Passed | Should-BeTrue
            @($result.OnlyLeft) | Should-BeCollection -Count 0
        }
    }
}
