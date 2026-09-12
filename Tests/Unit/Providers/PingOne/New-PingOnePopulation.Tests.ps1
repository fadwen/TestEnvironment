#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A seeded population is never the environment's default, and nothing can make it one.

    The default decides where every user created without a population lands, including users
    nothing to do with this module, so changing it is a change to how the environment behaves.
    It is a safety property with no parameter, and these tests exist so that adding -Default as a
    convenience is caught as the regression it would be.

    Every call is mocked. This suite must never reach an environment.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-PingOnePopulation' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-PingOneConnection {
                @{ EnvironmentId = '00000000-0000-4000-8000-000000000001'; Prefix = 'ZZ-TEST-'; EmailDomain = 'pingonelab.example.com' }
            }
            # Backstop: any call no test mocked fails loudly rather than reaching PingOne.
            Mock Invoke-PingOneRequest { throw "Escaped the mocks: $Method $Path" }
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' } { }
            $script:Bodies = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' } {
                $script:Bodies.Add($Body)
                [PSCustomObject]@{ id = [Guid]::NewGuid().ToString() }
            }
        }
    }

    It 'never sends a default flag when creating a population' {
        InModuleScope TestEnvironment {
            $null = New-PingOnePopulation -Confirm:$false
            $script:Bodies.Count | Should-BeGreaterThan 0
            @($script:Bodies | Where-Object { $_.ContainsKey('default') }) | Should-BeCollection -Count 0
        }
    }

    It 'has no parameter that could make a population the default' {
        InModuleScope TestEnvironment {
            (Get-Command New-PingOnePopulation).Parameters.Keys | Should-NotContainCollection 'Default'
        }
    }

    It 'writes the seed tag into the description' {
        InModuleScope TestEnvironment {
            $null = New-PingOnePopulation -Confirm:$false
            @($script:Bodies | Where-Object { -not ([string]$_.description).Contains('ZZ-TEST-seed') }) | Should-BeCollection -Count 0
        }
    }

    It 'reuses a population that already exists rather than creating a duplicate' {
        InModuleScope TestEnvironment {
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'GET' -and $Path -eq 'populations' } {
                [PSCustomObject]@{ id = 'existing'; name = 'ZZ-TEST-Staff' }
            }
            $result = New-PingOnePopulation -Key staff -PassThru -Confirm:$false
            $result.ReusedPopulations | Should-Be 1
            $result.CreatedPopulations | Should-Be 0
            Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-PingOnePopulation -WhatIf
            Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
