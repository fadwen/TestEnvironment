#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one exported command that reads two providers at once. It names its providers rather than
    reading the active one, because two are involved; it refuses a provider that is not loaded and
    the same provider twice; it reaches each provider's own snapshot reader and hands both to the
    comparison; and it says plainly, when a reader fails, that both providers must be connected in
    this session. Every provider folder on disk is held to having a snapshot reader, so a seventh
    provider is comparable the day its folder appears.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $script:ModuleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Compare-TestEnvironment' -Tag 'Unit', 'Public' {

    BeforeDiscovery {
        $script:Provider = @(Get-ChildItem -Path (Join-Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) 'Providers') -Directory |
                ForEach-Object { @{ Name = $_.Name } })
    }

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Get-EntraIdentitySnapshot {
                [PSCustomObject]@{ Provider = 'Entra'; Target = 'tenant-1'; Identities = @(
                        New-TestIdentity -Provider Entra -Login 'ZZ-TEST-jnino@lab.example.com' -Key 'jnino' -DisplayName 'José Niño' -Enabled $true
                        New-TestIdentity -Provider Entra -Login 'ZZ-TEST-awhitfield@lab.example.com' -Key 'awhitfield' -DisplayName 'Ada Whitfield' -Enabled $true
                    )
                }
            }
            Mock Get-PingOneIdentitySnapshot {
                [PSCustomObject]@{ Provider = 'PingOne'; Target = 'env-1'; Identities = @(
                        New-TestIdentity -Provider PingOne -Login 'zz-test-jnino' -Key 'jnino' -GivenName 'José' -Surname 'Niño' -Enabled $false
                    )
                }
            }
        }
    }

    It 'reads both providers through their own snapshot readers and returns the comparison' {
        InModuleScope TestEnvironment {
            $result = Compare-TestEnvironment -Provider Entra, PingOne -Quiet

            $result.PSObject.TypeNames[0] | Should-Be 'TestEnvironmentComparison'
            $result.Left.Provider | Should-Be 'Entra'
            $result.Right.Provider | Should-Be 'PingOne'
            $result.Matched | Should-Be 1
            @($result.OnlyLeft) | Should-BeCollection @('awhitfield (Ada Whitfield)')
            $result.Passed | Should-BeTrue
            Should-Invoke Get-EntraIdentitySnapshot -Times 1 -Exactly
            Should-Invoke Get-PingOneIdentitySnapshot -Times 1 -Exactly
            Should-NotInvoke Write-TestMessage
        }
    }

    It 'prints the counts, the matches, each side''s own people, the states and the verdict' {
        InModuleScope TestEnvironment {
            $null = Compare-TestEnvironment -Provider Entra, PingOne
            Should-Invoke Write-TestMessage -ParameterFilter { $Type -eq 'Header' -and $Message -like '*Entra and PingOne*' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Message -eq 'Entra: 2 people in tenant-1' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Message -eq 'Matched 1: 1 by login key, 0 by display name' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Message -eq 'Only in Entra: 1 (awhitfield (Ada Whitfield))' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Message -eq 'Only in PingOne: none' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Message -like 'Enabled differs for 1*' -and $Type -eq 'Info' }
            Should-Invoke Write-TestMessage -ParameterFilter { $Type -eq 'Success' -and $Message -like 'Names agree*' }
        }
    }

    It 'refuses a provider it does not know, and the same provider twice' {
        InModuleScope TestEnvironment {
            { Compare-TestEnvironment -Provider Entra, Nowhere -Quiet } | Should-Throw -ExceptionMessage "*No provider called 'Nowhere'*"
            { Compare-TestEnvironment -Provider Entra, Entra -Quiet } | Should-Throw -ExceptionMessage '*two different providers*'
            { Compare-TestEnvironment -Provider Entra -Quiet } | Should-Throw
        }
    }

    It 'says that both providers must be connected when one cannot be read' {
        InModuleScope TestEnvironment {
            Mock Get-PingOneIdentitySnapshot { throw 'Not connected to PingOne. Run Connect-PingOneEnvironment first.' }
            { Compare-TestEnvironment -Provider Entra, PingOne -Quiet } | Should-Throw -ExceptionMessage '*Both providers must be connected in this session*Not connected to PingOne*'
        }
    }

    It 'the <Name> provider implements Get-<Name>IdentitySnapshot' -ForEach $script:Provider {
        InModuleScope TestEnvironment -Parameters @{ Provider = $Name } {
            param($Provider)
            Get-Command -Name ('Get-{0}IdentitySnapshot' -f $Provider) -ErrorAction SilentlyContinue | Should-NotBeNull
        }
    }
}
