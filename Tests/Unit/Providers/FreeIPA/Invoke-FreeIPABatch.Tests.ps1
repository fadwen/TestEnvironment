#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The batch call the FreeIPA seed sends its users, hosts and DNS records through. What has
    to hold: the wire shape is the realm's - one batch method whose first argument is the list
    of commands, each with its arguments and options and the API version; a chunk carries no
    more than -ChunkSize commands; every command gets an answer in order; a refused command
    fails alone, or is ignored when its error name was expected; and a chunk the realm could not
    take fails every command in it with the same message, so nothing goes unanswered.

    Everything is mocked. The realm is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Invoke-FreeIPABatch' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ BaseUrl = 'https://ipa.example.com'; ApiVersion = '2.253' }
            $script:Batches = [System.Collections.Generic.List[object]]::new()
            # Answers every nested command with its own entry, unless the caller planted a refusal.
            $script:Refuse = @{}
            Mock Invoke-FreeIPARequest {
                $script:Batches.Add(@{ Method = $Method; Commands = @($Arguments); Options = $Options })
                $results = foreach ($call in @($Arguments)) {
                    $name = [string]$call.params[0][0]
                    if ($script:Refuse.ContainsKey($name)) {
                        [PSCustomObject]@{ error = $script:Refuse[$name].message; error_name = $script:Refuse[$name].name; error_code = 4002; result = $null }
                    }
                    else {
                        [PSCustomObject]@{ error = $null; result = [PSCustomObject]@{ uid = @($name) }; value = $name; summary = "Added $name" }
                    }
                }
                [PSCustomObject]@{ count = @($results).Count; results = @($results) }
            }
        }
    }

    It 'sends one batch method carrying the commands with their arguments, options and the API version, in chunks' {
        InModuleScope TestEnvironment {
            $commands = @(1..5 | ForEach-Object { @{ Method = 'user_add'; Arguments = @("u$_"); Options = @{ givenname = "G$_"; nothing = $null }; Tag = "u$_" } })
            $answers = @(Invoke-FreeIPABatch -Command $commands -ChunkSize 2 -Connection $script:Connection)

            $script:Batches.Count | Should-Be 3
            @($script:Batches | ForEach-Object { $_.Method } | Sort-Object -Unique) | Should-BeCollection @('batch')
            @($script:Batches | ForEach-Object { $_.Commands.Count }) | Should-BeCollection @(2, 2, 1)
            $first = $script:Batches[0].Commands[0]
            $first.method | Should-Be 'user_add'
            @($first.params[0]) | Should-BeCollection @('u1')
            $first.params[1].givenname | Should-Be 'G1'
            $first.params[1].version | Should-Be '2.253'
            # A null option is dropped rather than sent as null, as Invoke-FreeIPARequest drops it.
            $first.params[1].ContainsKey('nothing') | Should-BeFalse

            $answers.Count | Should-Be 5
            @($answers | ForEach-Object { $_.Command.Tag }) | Should-BeCollection @('u1', 'u2', 'u3', 'u4', 'u5')
            @($answers | Where-Object { -not $_.Success }) | Should-BeCollection -Count 0
            $answers[2].Result.result.uid | Should-BeCollection @('u3')
        }
    }

    It 'fails a refused command alone, ignores one whose error name was expected, and leaves the rest standing' {
        InModuleScope TestEnvironment {
            $script:Refuse['u2'] = @{ name = 'DuplicateEntry'; message = 'user with name "u2" already exists' }
            $script:Refuse['u3'] = @{ name = 'EmptyModlist'; message = 'no modifications to be performed' }
            $commands = @(
                @{ Method = 'user_add'; Arguments = @('u1'); Tag = 'u1' }
                @{ Method = 'user_add'; Arguments = @('u2'); Tag = 'u2' }
                @{ Method = 'user_mod'; Arguments = @('u3'); IgnoreError = @('EmptyModlist'); Tag = 'u3' }
            )
            $answers = @(Invoke-FreeIPABatch -Command $commands -Connection $script:Connection)

            $answers[0].Success | Should-BeTrue
            $answers[1].Success | Should-BeFalse
            $answers[1].ErrorName | Should-Be 'DuplicateEntry'
            $answers[1].ErrorMessage | Should-MatchString 'user_add failed \(DuplicateEntry 4002\): user with name "u2" already exists'
            $answers[2].Success | Should-BeTrue
            $answers[2].Ignored | Should-BeTrue
            $answers[2].Result | Should-BeNull
        }
    }

    It 'fails every command in a chunk the realm could not take, with the same message, and still answers the other chunks' {
        InModuleScope TestEnvironment {
            $script:Calls = 0
            Mock Invoke-FreeIPARequest {
                $script:Calls++
                if ($script:Calls -eq 1) { throw 'FreeIPA batch failed with HTTP 502: bad gateway' }
                [PSCustomObject]@{ results = @(foreach ($call in @($Arguments)) { [PSCustomObject]@{ error = $null; result = @{} } }) }
            }
            $commands = @(1..3 | ForEach-Object { @{ Method = 'host_add'; Arguments = @("h$_"); Tag = "h$_" } })
            $answers = @(Invoke-FreeIPABatch -Command $commands -ChunkSize 2 -Connection $script:Connection)

            @($answers | ForEach-Object { $_.Success }) | Should-BeCollection @($false, $false, $true)
            $answers[0].ErrorName | Should-Be 'BatchFailed'
            $answers[0].ErrorMessage | Should-MatchString 'HTTP 502'
            $answers[1].ErrorMessage | Should-Be $answers[0].ErrorMessage
        }
    }

    It 'reports a command the realm left unanswered rather than dropping it' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest { [PSCustomObject]@{ results = @([PSCustomObject]@{ error = $null; result = @{} }) } }
            $answers = @(Invoke-FreeIPABatch -Command @(@{ Method = 'host_add'; Arguments = @('h1') }, @{ Method = 'host_add'; Arguments = @('h2') }) -Connection $script:Connection)
            $answers[0].Success | Should-BeTrue
            $answers[1].Success | Should-BeFalse
            $answers[1].ErrorName | Should-Be 'NoAnswer'
        }
    }

    It 'sends nothing for no commands' {
        InModuleScope TestEnvironment {
            @(Invoke-FreeIPABatch -Command @() -Connection $script:Connection) | Should-BeCollection -Count 0
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}
