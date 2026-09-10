#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Base64url is where a JWT implementation quietly goes wrong, because a mistake here
    produces a well-formed token that Entra rejects with an error about the signature. The
    encoding is never named in the failure.

    The round-trip cases matter more than they look. Leading zero bytes survive base64 and
    disappear from anything that routes through a numeric type on the way back, so a decoder
    that looks correct on ASCII input can still lose the first byte of a signature.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-TestBase64Url' -Tag 'Unit' {

    It 'strips the padding base64 adds' {
        InModuleScope TestEnvironment {
            # 'M' encodes to 'TQ==' in standard base64. RFC 7515 requires the padding gone.
            $result = ConvertTo-TestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes('M'))
            $result | Should-Be 'TQ'
        }
    }

    It 'substitutes both URL-unsafe characters' {
        InModuleScope TestEnvironment {
            # These bytes are chosen to force a '+' and a '/' into the standard encoding.
            $bytes = [byte[]]@(0xFB, 0xFF, 0xBE)
            $standard = [Convert]::ToBase64String($bytes)
            $result = ConvertTo-TestBase64Url -Bytes $bytes

            # Proves the input actually exercises the substitution, so the test cannot pass
            # vacuously against an encoder that does nothing.
            $standard | Should-MatchString '[+/]'
            $result | Should-NotMatchString '[+/=]'
            $result | Should-Be ($standard.TrimEnd('=').Replace('+', '-').Replace('/', '_'))
        }
    }

    It 'encodes an empty array to an empty string' {
        InModuleScope TestEnvironment {
            ConvertTo-TestBase64Url -Bytes ([byte[]]@()) | Should-Be ''
        }
    }

    It 'round-trips every byte value exactly' {
        InModuleScope TestEnvironment {
            $original = [byte[]](0..255)
            $decoded = ConvertFrom-TestBase64Url -Text (ConvertTo-TestBase64Url -Bytes $original)

            $decoded.Count | Should-Be 256
            [Convert]::ToBase64String($decoded) | Should-Be ([Convert]::ToBase64String($original))
        }
    }

    It 'round-trips leading zero bytes without losing them' {
        InModuleScope TestEnvironment {
            # The case that catches a decoder routing through a numeric type. An RSA signature
            # beginning with a zero byte is not rare.
            $original = [byte[]]@(0, 0, 0, 42)
            $decoded = ConvertFrom-TestBase64Url -Text (ConvertTo-TestBase64Url -Bytes $original)

            $decoded.Count | Should-Be 4
            $decoded[0] | Should-Be 0
            $decoded[3] | Should-Be 42
        }
    }

    It 'round-trips at every padding length' {
        InModuleScope TestEnvironment {
            # One, two and three bytes over a multiple of three produce the three distinct
            # padding cases the decoder has to restore.
            foreach ($length in 1..9) {
                $original = [byte[]](1..$length)
                $decoded = ConvertFrom-TestBase64Url -Text (ConvertTo-TestBase64Url -Bytes $original)
                [Convert]::ToBase64String($decoded) | Should-Be ([Convert]::ToBase64String($original))
            }
        }
    }
}

Describe 'ConvertFrom-TestBase64Url' -Tag 'Unit' {

    It 'rejects a length that cannot be valid base64url' {
        InModuleScope TestEnvironment {
            # A length leaving one character over the four-character block cannot have come
            # from any byte sequence. Accepting it would mean silently returning wrong bytes.
            { ConvertFrom-TestBase64Url -Text 'ABCDE' -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*one character over*'
        }
    }

    It 'decodes what the encoder produced for a known string' {
        InModuleScope TestEnvironment {
            $decoded = ConvertFrom-TestBase64Url -Text 'eyJhbGciOiJSUzI1NiJ9'
            [System.Text.Encoding]::UTF8.GetString($decoded) | Should-Be '{"alg":"RS256"}'
        }
    }
}
