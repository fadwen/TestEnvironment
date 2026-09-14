#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Encryption at rest for every provider's durable credential: a service app private key that
    can mint admin-scoped tokens, a service account token or password.

    The failure mode these guard against is the quiet one: a value that looks encrypted and is
    not. ConvertFrom-SecureString returns a long hex string either way, so "it produced output"
    proves nothing. The tests therefore assert on the two properties that actually matter -
    the plaintext is not recoverable by inspection, and the round trip is exact - rather than
    on the shape of the result.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "protect-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    # Inside InModuleScope, $script: resolves to the MODULE's scope rather than this file's, so
    # the path has to be pushed across explicitly. Reading $script:Scratch in there without this
    # silently yields $null, which surfaces as "cannot bind argument to parameter 'Path'".
    InModuleScope TestEnvironment -Parameters @{ ScratchPath = $script:Scratch } {
        param($ScratchPath)
        $script:Scratch = $ScratchPath
    }
}

AfterAll {
    Remove-Item -Path $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Protect-TestSecret' -Tag 'Unit', 'Private' {

    It 'does not leave the plaintext recoverable by inspection' {
        InModuleScope TestEnvironment {
            $secret = 'kty-RSA-d-VERYSECRETKEYMATERIAL'
            $protected = Protect-TestSecret -PlainText $secret

            $protected.Value | Should-NotBe $secret
            $protected.Value.Contains('VERYSECRET') | Should-BeFalse
            $protected.Value.Contains($secret) | Should-BeFalse
        }
    }

    It 'round-trips exactly, including JSON punctuation and non-ASCII' {
        InModuleScope TestEnvironment {
            $secret = '{"kty":"RSA","note":"a `$dollar, a ''quote'' and Z' + [string][char]0xFC + 'rich"}'
            $protected = Protect-TestSecret -PlainText $secret

            Unprotect-TestSecret -Method $protected.Method -Value $protected.Value |
                Should-Be $secret
        }
    }

    It 'reports DPAPI on Windows so the caller can record what it wrote' {
        # The Method is written into the credential file and drives how it is read back, so a
        # wrong value here is unrecoverable rather than merely inaccurate.
        InModuleScope TestEnvironment {
            if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
                (Protect-TestSecret -PlainText 'x').Method | Should-Be 'DPAPI'
            }
        }
    }

    It 'never returns a value the plaintext can be read straight back out of' {
        # The regression, found by running on Linux. ConvertFrom-SecureString does not throw
        # off Windows and does not encrypt either - it returns the UTF-16 bytes of the
        # plaintext as hex, so 'SECRETKEYMATERIAL' came back as 5300450043... and decoded
        # straight back. The module recorded Protection = DPAPI and Encrypted = True for a
        # credential sitting in effective plaintext.
        #
        # This asserts the property rather than the platform, so it holds wherever it runs:
        # if the Method says DPAPI, the value must not be a hex encoding of the plaintext.
        InModuleScope TestEnvironment {
            $secret = 'SECRETKEYMATERIAL'
            $protected = Protect-TestSecret -PlainText $secret -WarningAction SilentlyContinue

            if ($protected.Method -eq 'DPAPI') {
                $isHex = $protected.Value -match '^[0-9a-fA-F]+$' -and
                    ($protected.Value.Length % 2) -eq 0
                if ($isHex) {
                    $raw = [byte[]]::new($protected.Value.Length / 2)
                    for ($i = 0; $i -lt $raw.Length; $i++) {
                        $raw[$i] = [Convert]::ToByte($protected.Value.Substring($i * 2, 2), 16)
                    }
                    [System.Text.Encoding]::Unicode.GetString($raw).Contains($secret) |
                        Should-BeFalse
                }
            }
        }
    }

    It 'claims DPAPI only on Windows' {
        InModuleScope TestEnvironment {
            $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
                ($PSVersionTable.PSObject.Properties['Platform'] -and
                    $PSVersionTable.Platform -eq 'Win32NT') -or ($env:OS -eq 'Windows_NT')

            $method = (Protect-TestSecret -PlainText 'x' -WarningAction SilentlyContinue).Method

            if ($onWindows) { $method | Should-Be 'DPAPI' } else { $method | Should-Be 'None' }
        }
    }

    It 'passes an unprotected value straight through when the method says None' {
        InModuleScope TestEnvironment {
            Unprotect-TestSecret -Method 'None' -Value 'plain' | Should-Be 'plain'
        }
    }

    It 'explains what to do when a DPAPI blob will not decrypt' {
        # DPAPI ties the secret to the user and the machine, so this is what a copied profile
        # looks like. The raw CryptographicException names none of that.
        InModuleScope TestEnvironment {
            { Unprotect-TestSecret -Method 'DPAPI' -Value 'deadbeefnotarealblob' } |
                Should-Throw -ExceptionMessage '*machine*'
        }
    }
}
