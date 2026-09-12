#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    New-TestPassword guarantees a character from each of four sets and then shuffles.
    Both halves have failed before: the shuffle was a Sort-Object on a random key, which is
    not uniform and left the four guaranteed characters clustered at the front.

    The distribution test below is written to be robust rather than clever. It asserts that
    an uppercase character is not ALWAYS first - which a broken shuffle guarantees and a
    working one makes vanishingly unlikely - instead of asserting a particular frequency,
    which would make the suite fail at random.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force

    $script:Sample = @(
        InModuleScope TestEnvironment { 1..120 | ForEach-Object { New-TestPassword -Length 16 } }
    )
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-TestPassword' -Tag 'Unit', 'Private' {

    Context 'Parameter validation' {

        It 'rejects a length below the documented minimum of 16' {
            # The AD provider generated from 8 characters upward; Core starts at 16. Nothing
            # asked for less - the two real callers use 16 and 24 - and a lab password short
            # enough to be worth attacking is not worth the parameter range that allows it.
            InModuleScope TestEnvironment {
                { New-TestPassword -Length 15 } | Should-Throw
            }
        }

        It 'rejects a length above the documented maximum of 128' {
            InModuleScope TestEnvironment {
                { New-TestPassword -Length 129 } | Should-Throw
            }
        }

        It 'defaults to 32 characters' {
            InModuleScope TestEnvironment {
                (New-TestPassword).Length | Should-Be 32
            }
        }
    }

    Context 'Core functionality' {

        It 'honours the requested length' -ForEach @(
            @{ Length = 16 }, @{ Length = 24 }, @{ Length = 32 }, @{ Length = 128 }
        ) {
            $requested = $Length
            $actual = InModuleScope TestEnvironment -Parameters @{ Len = $requested } {
                param($Len)
                (New-TestPassword -Length $Len).Length
            }

            $actual | Should-Be $requested
        }

        It 'returns a string' {
            $script:Sample[0] | Should-HaveType ([string])
        }

        It 'never returns the same password twice' {
            @($script:Sample | Sort-Object -Unique).Count | Should-Be $script:Sample.Count
        }
    }

    Context 'Complexity requirements' {

        It 'every password contains an uppercase character' {
            @($script:Sample | Where-Object { $_ -cnotmatch '[A-Z]' }).Count | Should-Be 0
        }

        It 'every password contains a lowercase character' {
            @($script:Sample | Where-Object { $_ -cnotmatch '[a-z]' }).Count | Should-Be 0
        }

        It 'every password contains a digit' {
            @($script:Sample | Where-Object { $_ -notmatch '\d' }).Count | Should-Be 0
        }

        It 'every password contains a special character' {
            $special = '[!#$%*+\-=?@]'
            @($script:Sample | Where-Object { $_ -notmatch $special }).Count | Should-Be 0
        }

        It 'meets complexity at the minimum length, where the slack is smallest' {
            # Four guaranteed characters in a sixteen-character password. An implementation that
            # filled first and guaranteed afterwards would fail here before anywhere else.
            $short = @(InModuleScope TestEnvironment {
                1..40 | ForEach-Object { New-TestPassword -Length 16 }
            })
            $special = '[!#$%*+\-=?@]'
            $bad = @($short | Where-Object {
                $_ -cnotmatch '[A-Z]' -or $_ -cnotmatch '[a-z]' -or $_ -notmatch '\d' -or $_ -notmatch $special
            })

            $bad.Count | Should-Be 0
        }
    }

    Context 'Shuffle quality' {

        It 'does not always place the guaranteed uppercase character first' {
            # The previous implementation shuffled with Sort-Object on a random key. That is
            # not a uniform shuffle, and the four guaranteed characters stayed near the
            # front. With a real shuffle the first character is uppercase sometimes, not
            # every time.
            $alwaysUpper = @($script:Sample | Where-Object { $_.Substring(0, 1) -cmatch '[A-Z]' }).Count
            $alwaysUpper | Should-BeLessThan $script:Sample.Count
        }

        It 'places a digit somewhere other than the third position at least once' {
            $thirdAlwaysDigit = @($script:Sample | Where-Object { $_.Substring(2, 1) -match '\d' }).Count
            $thirdAlwaysDigit | Should-BeLessThan $script:Sample.Count
        }
    }

    Context 'Forbidden substrings' {

        # Windows password complexity refuses any password containing the account's
        # sAMAccountName, or a token of its display name three characters or longer. Active
        # Directory reports it as "the password does not meet the length, complexity, or
        # history requirement of the domain", naming none of the three, so it reads as a weak
        # password rather than one that happened to spell a word in the account's own name.
        #
        # Measured against this generator across sixty thousand samples, that refused about
        # one seed run in three hundred: rare enough to look like a fluke, frequent enough to
        # be seen in a day of runs.

        It 'never returns a password containing a forbidden substring' {
            # Two hundred draws of a deliberately easy target. Without the guard a
            # three-letter substring turns up often enough to be caught here eventually,
            # which is the whole failure mode the guard removes.
            $hits = InModuleScope TestEnvironment {
                $found = 0
                1..200 | ForEach-Object {
                    $password = New-TestPassword -Length 16 -NotContaining 'Web'
                    if ($password.IndexOf('Web', [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found++ }
                }
                $found
            }
            $hits | Should-Be 0
        }

        It 'compares case-insensitively, because the directory does' {
            $hits = InModuleScope TestEnvironment {
                $found = 0
                1..200 | ForEach-Object {
                    $password = New-TestPassword -Length 16 -NotContaining 'abc'
                    if ($password -match '(?i)abc') { $found++ }
                }
                $found
            }
            $hits | Should-Be 0
        }

        It 'honours every substring it is given, not just the first' {
            $hits = InModuleScope TestEnvironment {
                $forbidden = @('Web', 'SQL', 'TEST', 'Dev')
                $found = 0
                1..100 | ForEach-Object {
                    $password = New-TestPassword -Length 16 -NotContaining $forbidden
                    foreach ($f in $forbidden) {
                        if ($password.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found++ }
                    }
                }
                $found
            }
            $hits | Should-Be 0
        }

        It 'still satisfies the character classes after regenerating' {
            # The guard must discard whole candidates, not edit them. Editing one to remove a
            # substring is how a password loses the class that made it acceptable.
            $password = InModuleScope TestEnvironment {
                New-TestPassword -Length 16 -NotContaining @('Web', 'SQL', 'Dev')
            }
            $password | Should-MatchString '[A-Z]'
            $password | Should-MatchString '[a-z]'
            $password | Should-MatchString '[0-9]'
            $password | Should-MatchString '[!#$%*+\-=?@]'
        }

        It 'ignores an empty or null entry rather than refusing everything' {
            # An empty string is contained in every password. Treating it as a real
            # constraint would spin to the attempt ceiling and then throw.
            $length = InModuleScope TestEnvironment {
                (New-TestPassword -Length 16 -NotContaining @('', $null, 'Web')).Length
            }
            $length | Should-Be 16
        }

        It 'throws rather than hanging when the request cannot be satisfied' {
            # Forbidding most of the alphabet one character at a time cannot be satisfied.
            # Better a clear error than a seed that never returns.
            {
                InModuleScope TestEnvironment {
                    New-TestPassword -Length 16 -NotContaining ([string[]](
                            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'j', 'k', 'm', 'n', 'p', 'q',
                            'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '2', '3', '4', '5', '6',
                            '7', '8', '9', '!', '#', '$', '%', '*', '+', '-', '=', '?', '@'))
                }
            } | Should-Throw
        }

        It 'behaves as before when no substrings are given' {
            $length = InModuleScope TestEnvironment { (New-TestPassword -Length 24).Length }
            $length | Should-Be 24
        }
    }

    Context 'Implementation constraints' {

        It 'does not use the obsolete RNGCryptoServiceProvider' {
            # Obsolete from .NET 6. Still functional, so nothing fails loudly if it comes
            # back - which is exactly why it needs a test.
            #
            # Checked against code tokens only. The help block in that file explains why the
            # type was replaced and therefore names it; matching raw text would fail on the
            # explanation rather than on a use.
            $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
            $path = Join-Path $moduleRoot 'Core\New-TestPassword.ps1'

            # Asserted before parsing, because a path that no longer resolves produces no
            # tokens, and a search for a forbidden string through no tokens passes. This test
            # went on passing while pointing at the function's old home in Private.
            Test-Path -LiteralPath $path | Should-BeTrue

            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$null)
            $code = ($tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' '

            $code | Should-NotMatchString 'RNGCryptoServiceProvider'
        }
    }
}
