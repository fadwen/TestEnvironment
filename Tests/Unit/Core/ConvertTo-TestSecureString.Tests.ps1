#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

# The equivalence test below calls ConvertTo-SecureString -AsPlainText on purpose: the
# helper's contract is to produce the same result as the cmdlet it replaces, and the only
# way to assert that is to run both. The value is a literal in a test file, not a credential.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Deliberate comparison against the cmdlet the helper replaces.')]
param()

<#
    ConvertTo-TestSecureString exists so passwords are not handed to a cmdlet as plain
    text. Its whole value is that the result is identical to what ConvertTo-SecureString
    would have produced, so these tests are mostly about round-tripping exactly - including
    the characters a naive character-by-character copy tends to mangle.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force

    function Get-PlainFromSecure {
        param([System.Security.SecureString]$Secure)

        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-TestSecureString' -Tag 'Unit', 'Private' {

    Context 'Parameter validation' {

        It 'rejects an empty string' {
            InModuleScope TestEnvironment {
                { ConvertTo-TestSecureString -PlainText '' } | Should-Throw
            }
        }

        It 'rejects null' {
            InModuleScope TestEnvironment {
                { ConvertTo-TestSecureString -PlainText $null } | Should-Throw
            }
        }
    }

    Context 'Core functionality' {

        It 'returns a SecureString' {
            $result = InModuleScope TestEnvironment { ConvertTo-TestSecureString -PlainText 'abc' }
            $result | Should-HaveType ([System.Security.SecureString])
        }

        It 'returns it read-only, so it cannot be altered afterwards' {
            $result = InModuleScope TestEnvironment { ConvertTo-TestSecureString -PlainText 'abc' }
            $result.IsReadOnly() | Should-BeTrue
        }

        It 'reports the correct length' {
            $result = InModuleScope TestEnvironment { ConvertTo-TestSecureString -PlainText 'abcdefgh' }
            $result.Length | Should-Be 8
        }

        It 'round-trips <Label> exactly' -ForEach @(
            @{ Label = 'a simple value';        Value = 'Password123!' }
            @{ Label = 'a single character';    Value = 'x' }
            @{ Label = 'every special the generator uses'; Value = '!@#$%^&*()_+-=[]{}|;:,.<>?' }
            @{ Label = 'embedded quotes';       Value = "it's a `"quote`"" }
            @{ Label = 'a dollar sign';         Value = 'costs $5 $notAVariable' }
            @{ Label = 'a backtick';            Value = 'tick`here' }
            @{ Label = 'non-ASCII';             Value = 'Ren' + [char]0xE9 + 'e-Z' + [char]0xFC + 'rich' }
            @{ Label = 'a long value';          Value = ('A1!b' * 32) }
        ) {
            # $expected, not $input - $input is an automatic variable holding the pipeline
            # enumerator, and assigning to it is both a PSScriptAnalyzer error and a good
            # way to get confusing behaviour inside a pipeline.
            $expected = $Value
            $secure = InModuleScope TestEnvironment -Parameters @{ Text = $expected } {
                param($Text)
                ConvertTo-TestSecureString -PlainText $Text
            }

            Get-PlainFromSecure -Secure $secure | Should-Be $expected
        }

        It 'produces the same value as ConvertTo-SecureString would have' {
            # The point of the helper is to be a drop-in replacement. If it ever stops
            # matching, callers have silently changed behaviour.
            $text = 'Equivalence!42'
            $mine = InModuleScope TestEnvironment -Parameters @{ Text = $text } {
                param($Text)
                ConvertTo-TestSecureString -PlainText $Text
            }
            $builtIn = ConvertTo-SecureString -String $text -AsPlainText -Force

            Get-PlainFromSecure -Secure $mine | Should-Be (Get-PlainFromSecure -Secure $builtIn)
        }
    }
}
