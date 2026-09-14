#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The runspace pool behind the Authentik seed and teardown. These run real workers, because
    what has to be true is exactly what a mock could not show: that the block runs inside the
    module in a fresh runspace and can call a private function there, that results come back one
    per item in input order whatever order the workers finish in, that one item's exception fails
    that item alone, and that nothing from the session travels across. They reach no network:
    the blocks compute and return.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Invoke-TestParallel' -Tag 'Unit', 'Private' {

    It 'returns one result per item in input order, with the item, its output and what was passed in' {
        InModuleScope TestEnvironment {
            $results = @(Invoke-TestParallel -InputObject 3, 1, 2 -ThrottleLimit 3 -Parameter @{ Factor = 10 } -ScriptBlock {
                    param($Item, $Parameter)
                    # The slowest first, so finishing order is the reverse of input order.
                    Start-Sleep -Milliseconds (50 * $Item)
                    $Item * $Parameter.Factor
                })

            $results.Count | Should-Be 3
            @($results | ForEach-Object { $_.Index }) | Should-BeCollection @(0, 1, 2)
            @($results | ForEach-Object { $_.Input }) | Should-BeCollection @(3, 1, 2)
            @($results | ForEach-Object { $_.Output[0] }) | Should-BeCollection @(30, 10, 20)
            @($results | Where-Object { -not $_.Success }) | Should-BeCollection -Count 0
        }
    }

    It 'runs the block inside the module, where a private function is in reach' {
        InModuleScope TestEnvironment {
            $results = @(Invoke-TestParallel -InputObject 'ZZ-TEST-' -ThrottleLimit 1 -ScriptBlock {
                    param($Item)
                    (Get-TestSeedMarker -Prefix $Item).Tag
                })
            $results[0].Success | Should-BeTrue
            $results[0].Output[0] | Should-Be 'ZZ-TEST-seed'
        }
    }

    It 'fails the one item whose block throws, with its message, and leaves the others standing' {
        InModuleScope TestEnvironment {
            $results = @(Invoke-TestParallel -InputObject 'a', 'boom', 'c' -ThrottleLimit 2 -ScriptBlock {
                    param($Item)
                    if ($Item -eq 'boom') { throw "no $Item today" }
                    $Item.ToUpperInvariant()
                })

            @($results | ForEach-Object { $_.Success }) | Should-BeCollection @($true, $false, $true)
            $results[1].Error | Should-MatchString 'no boom today'
            @($results[1].Output) | Should-BeCollection -Count 0
            $results[2].Output[0] | Should-Be 'C'
        }
    }

    It 'sees none of the session''s state: the active connection is not there' {
        InModuleScope TestEnvironment {
            $script:AuthentikConnection = @{ BaseUrl = 'https://auth.example.com' }
            try {
                $results = @(Invoke-TestParallel -InputObject 1 -ThrottleLimit 1 -ScriptBlock {
                        param($Item)
                        [bool]$script:AuthentikConnection -and $Item
                    })
                $results[0].Output[0] | Should-BeFalse
            }
            finally { $script:AuthentikConnection = $null }
        }
    }

    It 'returns nothing for no items' {
        InModuleScope TestEnvironment {
            @(Invoke-TestParallel -InputObject @() -ScriptBlock { param($Item) $Item }) | Should-BeCollection -Count 0
        }
    }
}
