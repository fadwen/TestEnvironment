#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one shape every Test-<Provider>Environment result takes. Pinned here once, so the
    per-provider suites can be about their own naming rules: identifiers are compared as sets with
    the missing and unexpected named on both sides, a name check tells a decomposed and a
    precomposed string apart where -eq would not, a membership check judges what is missing only,
    an observational count takes no part in the verdict, and the verdict is the conjunction of
    every check that has one.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'New-TestEnvironmentCheck' -Tag 'Unit', 'Private' {

    It 'names what is missing and what is unexpected, sorted, and fails when either exists' {
        InModuleScope TestEnvironment {
            $check = New-TestEnvironmentCheck -Name 'Users' -Expected 'c', 'a', 'b' -Found 'a', 'd', 'b', 'e'
            $check.Kind | Should-Be 'Identity'
            $check.Expected | Should-Be 3
            $check.Found | Should-Be 4
            @($check.Missing) | Should-BeCollection @('c')
            @($check.Unexpected) | Should-BeCollection @('d', 'e')
            $check.Passed | Should-BeFalse
        }
    }

    It 'passes when the sets agree, whatever the order, and ignores empty identifiers' {
        InModuleScope TestEnvironment {
            $check = New-TestEnvironmentCheck -Name 'Groups' -Expected 'b', 'a', '' -Found 'a', $null, 'b'
            $check.Passed | Should-BeTrue
            $check.Expected | Should-Be 2
            @($check.Missing) | Should-BeCollection -Count 0
            @($check.Unexpected) | Should-BeCollection -Count 0
        }
    }

    It 'compares identifiers exactly unless asked to ignore case' {
        InModuleScope TestEnvironment {
            (New-TestEnvironmentCheck -Name 'x' -Expected 'Alice' -Found 'alice').Passed | Should-BeFalse
            (New-TestEnvironmentCheck -Name 'x' -Expected 'Alice' -Found 'alice' -IgnoreCase).Passed | Should-BeTrue
        }
    }

    It 'tells a decomposed name from a precomposed one, which -eq does not' {
        InModuleScope TestEnvironment {
            $precomposed = 'Jos' + [string][char]0x00E9
            $decomposed = 'Jose' + [string][char]0x0301
            ($precomposed -eq $decomposed) | Should-BeTrue
            $check = New-TestEnvironmentCheck -Name 'Names' -Expected $precomposed -Found $decomposed
            $check.Passed | Should-BeFalse
            @($check.Missing) | Should-BeCollection @($precomposed)
            @($check.Unexpected) | Should-BeCollection @($decomposed)
        }
    }

    It 'judges a membership check on what is missing only' {
        InModuleScope TestEnvironment {
            $check = New-TestEnvironmentCheck -Name 'Memberships' -Expected 'g <- a', 'g <- b' -Found 'g <- a', 'g <- b', 'g <- rule-added' -MissingOnly
            $check.Passed | Should-BeTrue
            @($check.Unexpected) | Should-BeCollection -Count 0

            $short = New-TestEnvironmentCheck -Name 'Memberships' -Expected 'g <- a', 'g <- b' -Found 'g <- a' -MissingOnly
            $short.Passed | Should-BeFalse
            @($short.Missing) | Should-BeCollection @('g <- b')
        }
    }

    It 'records value mismatches as the check that failed' {
        InModuleScope TestEnvironment {
            $check = New-TestEnvironmentCheck -Name 'User display names' -Compared 10 -Mismatch @("jnino: 'Jose' should be 'José'")
            $check.Kind | Should-Be 'Value'
            $check.Expected | Should-Be 10
            $check.Found | Should-Be 9
            @($check.Missing).Count | Should-Be 1
            $check.Passed | Should-BeFalse
            (New-TestEnvironmentCheck -Name 'x' -Compared 3 -Mismatch @()).Passed | Should-BeTrue
        }
    }

    It 'judges a count against its expectation, and records one without an expectation as observational' {
        InModuleScope TestEnvironment {
            (New-TestEnvironmentCheck -Name 'Guests' -FoundCount 4 -ExpectedCount 4).Passed | Should-BeTrue
            (New-TestEnvironmentCheck -Name 'Guests' -FoundCount 3 -ExpectedCount 4).Passed | Should-BeFalse
            $observed = New-TestEnvironmentCheck -Name 'Conditional Access policies' -FoundCount 3
            $observed.Passed | Should-BeNull
            $observed.Expected | Should-BeNull
            $observed.Found | Should-Be 3
        }
    }
}

Describe 'New-TestEnvironmentVerification' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Lines = New-Object System.Collections.Generic.List[object]
            Mock Write-TestMessage { $script:Lines.Add([PSCustomObject]@{ Message = $Message; Type = $Type }) }
            $script:Checks = @(
                New-TestEnvironmentCheck -Name 'Users' -Expected 'a', 'b' -Found 'a', 'b'
                New-TestEnvironmentCheck -Name 'Groups' -Expected 'g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7' -Found 'g1', 'extra'
                New-TestEnvironmentCheck -Name 'Names' -Compared 2 -Mismatch @("x: 'a' should be 'b'")
                New-TestEnvironmentCheck -Name 'Policies' -FoundCount 2
            )
        }
    }

    It 'fails on any failed check, counts them, and leaves an observational count out of the verdict' {
        InModuleScope TestEnvironment {
            $result = New-TestEnvironmentVerification -Provider 'Okta' -Target 'https://dev-1.okta.com' -Check $script:Checks
            $result.Provider | Should-Be 'Okta'
            $result.Target | Should-Be 'https://dev-1.okta.com'
            $result.Passed | Should-BeFalse
            $result.Failed | Should-Be 2
            @($result.Checks).Count | Should-Be 4

            $passing = New-TestEnvironmentVerification -Provider 'Okta' -Check @($script:Checks[0], $script:Checks[3]) -Quiet
            $passing.Passed | Should-BeTrue
            $passing.Failed | Should-Be 0
        }
    }

    It 'does not pass when every check is observational, because nothing was judged' {
        InModuleScope TestEnvironment {
            $result = New-TestEnvironmentVerification -Provider 'Entra' -Check @($script:Checks[3]) -Quiet
            $result.Passed | Should-BeFalse
            $result.Failed | Should-Be 0
        }
    }

    It 'prints one line per check in the type its outcome deserves, samples long lists, and a verdict' {
        InModuleScope TestEnvironment {
            $null = New-TestEnvironmentVerification -Provider 'Okta' -Target 'org' -Check $script:Checks

            $script:Lines[0].Type | Should-Be 'Header'
            $script:Lines[0].Message | Should-MatchString 'Okta seed against org'
            @($script:Lines | Where-Object { $_.Message -like 'Users: 2 of 2 present' -and $_.Type -eq 'Success' }).Count | Should-Be 1
            $groups = @($script:Lines | Where-Object { $_.Message -like 'Groups:*' })[0]
            $groups.Type | Should-Be 'Warning'
            $groups.Message | Should-MatchString '1 of 7 present'
            $groups.Message | Should-MatchString 'missing: g2, g3, g4, g5, g6 and 1 more'
            $groups.Message | Should-MatchString 'unexpected: extra'
            @($script:Lines | Where-Object { $_.Message -like "Names: 1 of 2 differ; differing: x: 'a' should be 'b'" }).Count | Should-Be 1
            @($script:Lines | Where-Object { $_.Message -eq 'Policies: 2 found' -and $_.Type -eq 'Info' }).Count | Should-Be 1
            $script:Lines[-1].Type | Should-Be 'Error'
            $script:Lines[-1].Message | Should-Be 'Not verified: 2 of 3 checks failed.'
        }
    }

    It 'says how many of the expected are present, never more of them than the data lists' {
        InModuleScope TestEnvironment {
            # A membership check can find more than the data lists and still pass.
            $null = New-TestEnvironmentVerification -Provider 'Okta' -Check @(New-TestEnvironmentCheck -Name 'Memberships' -Expected 'g <- a' -Found 'g <- a', 'g <- rule' -MissingOnly)
            @($script:Lines | Where-Object { $_.Message -eq 'Memberships: 1 of 1 present' }).Count | Should-Be 1
        }
    }

    It 'prints nothing under -Quiet' {
        InModuleScope TestEnvironment {
            $null = New-TestEnvironmentVerification -Provider 'Okta' -Check $script:Checks -Quiet
            Should-NotInvoke Write-TestMessage
        }
    }
}

Describe 'Format-TestEnvironmentSample' -Tag 'Unit', 'Private' {

    It 'shows the first few and counts the rest' {
        InModuleScope TestEnvironment {
            Format-TestEnvironmentSample -Item @() | Should-Be ''
            Format-TestEnvironmentSample -Item 'a', 'b' | Should-Be 'a, b'
            Format-TestEnvironmentSample -Item 'a', 'b', 'c' -Limit 2 | Should-Be 'a, b and 1 more'
        }
    }
}
