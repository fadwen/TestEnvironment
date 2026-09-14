#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Repair re-runs only the seed steps that own what verification found missing, then verifies
    again. What has to hold: nothing runs when everything passes; the steps come from the
    provider's own map plus what it says every repair needs, and everything else is skipped by
    name through the orchestrator's -Skip; -WhatIf names the steps and runs none; an unexpected
    object is reported and left alone; and every provider's map covers every check its verifier
    judges, so a new check cannot appear without saying which step puts it back. That last one
    is read from the verifier's source, so it holds the day a check is added.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $script:ModuleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Repair-TestEnvironment' -Tag 'Unit', 'Public' {

    BeforeDiscovery {
        $script:Provider = @(Get-ChildItem -Path (Join-Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) 'Providers') -Directory |
                ForEach-Object { @{ Name = $_.Name } })
    }

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = 'PingOne'
            Mock Write-TestMessage { }
            $script:Verdicts = New-Object System.Collections.Generic.List[object]
            Mock Test-PingOneEnvironment { $script:Verdicts[0]; if ($script:Verdicts.Count -gt 1) { $script:Verdicts.RemoveAt(0) } }
            Mock New-PingOneEnvironment { [PSCustomObject]@{ PSTypeName = 'PingOneEnvironmentResult'; Skipped = @($Skip) } }
            $script:Failing = [PSCustomObject]@{ Passed = $false; Checks = @(
                    New-TestEnvironmentCheck -Name 'Populations' -Expected 'a' -Found 'a'
                    New-TestEnvironmentCheck -Name 'Users' -Expected 'zz-test-jnino', 'zz-test-mbell' -Found 'zz-test-jnino', 'zz-test-stray'
                    New-TestEnvironmentCheck -Name 'Group memberships' -Expected 'g <- u' -Found @() -MissingOnly
                    New-TestEnvironmentCheck -Name 'Attributes' -FoundCount 5
                )
            }
            $script:Passing = [PSCustomObject]@{ Passed = $true; Checks = @(New-TestEnvironmentCheck -Name 'Users' -Expected 'a' -Found 'a') }
        }
    }

    AfterEach {
        InModuleScope TestEnvironment { $script:ActiveProvider = $null }
    }

    It 'runs nothing when every check passes' {
        InModuleScope TestEnvironment {
            $script:Verdicts.Add($script:Passing)
            $result = Repair-TestEnvironment
            $result.Repaired | Should-BeTrue
            @($result.StepsRun) | Should-BeCollection -Count 0
            Should-NotInvoke New-PingOneEnvironment
            Should-Invoke Test-PingOneEnvironment -Times 1 -Exactly
        }
    }

    It 're-runs only the steps that own what failed, skipping every other step by name, and verifies again' {
        InModuleScope TestEnvironment {
            $script:Verdicts.Add($script:Failing)
            $script:Verdicts.Add($script:Passing)

            $result = Repair-TestEnvironment -SkipMembership

            # Users and Group memberships both belong to the users step on PingOne; Populations passed.
            @($result.StepsRun) | Should-BeCollection @('Users')
            Should-Invoke New-PingOneEnvironment -Times 1 -Exactly -ParameterFilter { $PassThru -and (@($Skip | Sort-Object) -join ',') -eq 'Applications,Attributes,Groups,Populations,Resources' }
            Should-Invoke Test-PingOneEnvironment -Times 2 -Exactly -ParameterFilter { $Quiet -and $SkipMembership }
            $result.Repaired | Should-BeTrue
            $result.After.Passed | Should-BeTrue
            $result.SeedResult.Skipped | Should-ContainCollection 'Groups'
            # The stray user is reported and left alone.
            Should-Invoke Write-TestMessage -ParameterFilter { $Type -eq 'Warning' -and $Message -like 'Users: 1 object(s) the data does not describe are left alone*zz-test-stray*' }
        }
    }

    It 'names the steps and runs none of them under -WhatIf' {
        InModuleScope TestEnvironment {
            $script:Verdicts.Add($script:Failing)
            $result = Repair-TestEnvironment -WhatIf
            @($result.StepsRun) | Should-BeCollection @('Users')
            $result.After | Should-BeNull
            $result.Repaired | Should-BeNull
            Should-NotInvoke New-PingOneEnvironment
        }
    }

    It 'says so when the second verification still fails' {
        InModuleScope TestEnvironment {
            $script:Verdicts.Add($script:Failing)
            $script:Verdicts.Add($script:Failing)
            $result = Repair-TestEnvironment
            $result.Repaired | Should-BeFalse
            Should-Invoke Write-TestMessage -ParameterFilter { $Type -eq 'Warning' -and $Message -like 'Not repaired: 2 check(s) still fail*' }
        }
    }

    It 'refuses to run before anything is connected' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = $null
            { Repair-TestEnvironment } | Should-Throw -ExceptionMessage '*Not connected*'
        }
    }

    It 'the <Name> provider''s repair map covers every check its verifier judges, with steps the orchestrator knows' -ForEach $script:Provider {
        InModuleScope TestEnvironment -Parameters @{ Provider = $Name; ModuleRoot = $script:ModuleRoot } {
            param($Provider, $ModuleRoot)
            $map = Get-Variable -Name ('{0}RepairStep' -f $Provider) -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            $map | Should-NotBeNull

            # Every judged check the verifier builds: a New-TestEnvironmentCheck call with a
            # literal -Name that is not an observational count (-FoundCount with no -ExpectedCount).
            $file = Join-Path $ModuleRoot ('Providers\{0}\Public\Test-{0}Environment.ps1' -f $Provider)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
            $judged = foreach ($call in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-TestEnvironmentCheck' }, $true)) {
                $parameters = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
                if ($parameters -contains 'FoundCount' -and $parameters -notcontains 'ExpectedCount') { continue }
                $nameIndex = [array]::IndexOf(@($call.CommandElements | ForEach-Object { if ($_ -is [System.Management.Automation.Language.CommandParameterAst]) { $_.ParameterName } else { $null } }), 'Name')
                $value = $call.CommandElements[$nameIndex + 1]
                if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $value.Value }
            }
            @($judged).Count | Should-BeGreaterThan 0
            $uncovered = @($judged | Where-Object { -not $map.Step.ContainsKey($_) })
            ($uncovered -join ', ') | Should-Be ''

            $steps = @(@((Get-Command -Name ('New-{0}Environment' -f $Provider)).Parameters['Skip'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0].ValidValues)
            $unknown = @(@($map.Step.Values) + @($map.Always) | Sort-Object -Unique | Where-Object { $steps -notcontains $_ })
            ($unknown -join ', ') | Should-Be ''
        }
    }
}
