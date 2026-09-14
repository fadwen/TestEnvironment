#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The verification dispatcher. Two things matter: that it reaches the connected provider's own
    command with the caller's parameters intact, and that every provider on disk has such a
    command - a provider that seeds and tears down but cannot be verified would make
    Test-TestEnvironment fail at run time for the one provider somebody happened to connect to.
    The second is driven off the Providers folder rather than a list, so a seventh provider is
    held to it the day its folder appears.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $script:ModuleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Test-TestEnvironment' -Tag 'Unit', 'Public' {

    BeforeDiscovery {
        $script:Provider = @(Get-ChildItem -Path (Join-Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) 'Providers') -Directory |
                ForEach-Object { @{ Name = $_.Name } })
    }

    AfterEach {
        InModuleScope TestEnvironment { $script:ActiveProvider = $null }
    }

    It 'refuses to run before anything is connected' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = $null
            { Test-TestEnvironment } | Should-Throw -ExceptionMessage '*Not connected*'
        }
    }

    It 'forwards to the connected provider with the mirrored parameters bound' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = 'Okta'
            Mock Test-OktaEnvironment { [PSCustomObject]@{ PSTypeName = 'TestEnvironmentVerification'; Provider = 'Okta'; Passed = $true } }

            $result = Test-TestEnvironment -SkipMembership -Quiet
            $result.Provider | Should-Be 'Okta'
            Should-Invoke Test-OktaEnvironment -Times 1 -Exactly -ParameterFilter { $SkipMembership -and $Quiet }
        }
    }

    It 'rejects a parameter the provider does not have at binding' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = 'Okta'
            Mock Test-OktaEnvironment { }
            { Test-TestEnvironment -NoSuchSwitch } | Should-Throw
            Should-NotInvoke Test-OktaEnvironment
        }
    }

    It 'the <Name> provider implements Test-<Name>Environment with -SkipMembership and -Quiet' -ForEach $script:Provider {
        InModuleScope TestEnvironment -Parameters @{ Provider = $Name } {
            param($Provider)
            $command = Get-Command -Name ('Test-{0}Environment' -f $Provider) -ErrorAction SilentlyContinue
            $command | Should-NotBeNull
            $command.Parameters.Keys | Should-ContainCollection @('SkipMembership', 'Quiet')
        }
    }
}
