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
