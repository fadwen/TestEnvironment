#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one teardown question. What matters is the answer when nobody can answer: a host that
    cannot prompt throws from ShouldContinue, and that must read as a refusal, because an
    unattended teardown has to say -Force. The cmdlet is stood in for by an object with a
    ShouldContinue method, so the test itself never depends on the host it runs under.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}


Describe 'Confirm-TestTeardown' -Tag 'Unit', 'Private', 'Safety' {

    It 'passes the question and caption to the cmdlet and returns its answer' -ForEach @(
        @{ Answer = $true }
        @{ Answer = $false }
    ) {
        InModuleScope TestEnvironment -Parameters @{ Answer = $Answer } {
            param($Answer)
            $asked = @{}
            $cmdlet = [PSCustomObject]@{ Answer = $Answer }
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldContinue -Value {
                param($q, $c)
                $asked['Question'] = $q; $asked['Caption'] = $c
                $this.Answer
            }

            $result = Confirm-TestTeardown -Cmdlet $cmdlet -Question 'Remove everything?' -Caption 'Remove test environment'

            $result | Should-Be $Answer
            $asked['Question'] | Should-Be 'Remove everything?'
            $asked['Caption'] | Should-Be 'Remove test environment'
        }
    }

    It 'treats a host that cannot ask as a refusal, never as a yes' {
        InModuleScope TestEnvironment {
            $cmdlet = [PSCustomObject]@{}
            $cmdlet | Add-Member -MemberType ScriptMethod -Name ShouldContinue -Value {
                throw 'A command that prompts the user failed because the host program or the command type does not support user interaction.'
            }

            Confirm-TestTeardown -Cmdlet $cmdlet -Question 'q' -Caption 'c' | Should-BeFalse
        }
    }
}
