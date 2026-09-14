#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one HTTP call. Windows PowerShell 5.1 corrupts non-ASCII text on the way out and on the
    way back, and PowerShell 7 hides both faults, so these pin the four things the helper exists
    for in terms that fail on either edition: the body reaches Invoke-WebRequest as UTF-8 bytes
    with the charset named, the response is decoded from its raw stream and not from .Content,
    the progress preference comes back whether the call threw or not, and an error propagates
    untouched so a provider can still read the response it carries.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-TestWebRequest' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            # A response whose .Content was decoded as Latin-1, the way 5.1 does it, and whose raw
            # stream holds the real UTF-8. Reading the wrong one is visible in the result.
            $script:Utf8 = [System.Text.Encoding]::UTF8.GetBytes('{"name":"José Niño 姜"}')
            $script:Respond = {
                [PSCustomObject]@{
                    StatusCode       = 200
                    Headers          = @{ 'Content-Type' = 'application/json' }
                    Content          = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($script:Utf8)
                    RawContentStream = [System.IO.MemoryStream]::new($script:Utf8)
                }
            }
            $script:Sent = $null
            Mock Invoke-WebRequest {
                $script:Sent = @{ Body = $Body; ContentType = $ContentType; Headers = $Headers; Method = $Method; Uri = $Uri; Bound = @($PSBoundParameters.Keys) }
                & $script:Respond
            }
        }
    }

    It 'sends a string body as UTF-8 bytes with the charset named, never as a string' {
        InModuleScope TestEnvironment {
            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method POST -Body '{"name":"Zoë"}'

            $script:Sent.Body -is [byte[]] | Should-BeTrue
            [System.Text.Encoding]::UTF8.GetString($script:Sent.Body) | Should-Be '{"name":"Zoë"}'
            $script:Sent.ContentType | Should-Be 'application/json; charset=utf-8'
        }
    }

    It 'serialises an object body to JSON and sends that as UTF-8 bytes' {
        InModuleScope TestEnvironment {
            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method POST -Body @{ name = '姜俊誉' }

            ([System.Text.Encoding]::UTF8.GetString($script:Sent.Body) | ConvertFrom-Json).name | Should-Be '姜俊誉'
        }
    }

    It 'sends a byte array as it stands, with the content type the caller names' {
        InModuleScope TestEnvironment {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('grant_type=client_credentials')
            $null = Invoke-TestWebRequest -Uri 'https://login.example.com/token' -Method POST -Body $bytes -ContentType 'application/x-www-form-urlencoded'

            [object]::ReferenceEquals($script:Sent.Body, $bytes) | Should-BeTrue
            $script:Sent.ContentType | Should-Be 'application/x-www-form-urlencoded'
        }
    }

    It 'sends no body and no content type for a request without one' {
        InModuleScope TestEnvironment {
            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET -Headers @{ Authorization = 'Bearer t' }

            $script:Sent.Bound | Should-NotContainCollection 'Body'
            $script:Sent.Bound | Should-NotContainCollection 'ContentType'
            $script:Sent.Headers['Authorization'] | Should-Be 'Bearer t'
        }
    }

    It 'decodes the response from its raw bytes as UTF-8 rather than from .Content' {
        InModuleScope TestEnvironment {
            $r = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET

            ($r.Content | ConvertFrom-Json).name | Should-Be 'José Niño 姜'
            $r.StatusCode | Should-Be 200
            $r.Headers['Content-Type'] | Should-Be 'application/json'
        }
    }

    It 'returns empty content for a response with no body, such as a 204' {
        InModuleScope TestEnvironment {
            $script:Respond = { [PSCustomObject]@{ StatusCode = 204; Headers = @{}; Content = $null; RawContentStream = [System.IO.MemoryStream]::new() } }

            (Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method DELETE).Content | Should-Be ''
        }
    }

    It 'suppresses the progress bar for the call and restores the preference, even when the call throws' {
        InModuleScope TestEnvironment {
            $ProgressPreference = 'Continue'
            $script:Seen = $null
            Mock Invoke-WebRequest { $script:Seen = $ProgressPreference; & $script:Respond }

            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET
            $script:Seen | Should-Be 'SilentlyContinue'
            $ProgressPreference | Should-Be 'Continue'

            Mock Invoke-WebRequest { throw 'boom' }
            { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET } | Should-Throw
            $ProgressPreference | Should-Be 'Continue'
        }
    }

    It 'lets an error propagate untouched, so the caller still has the response it carries' {
        InModuleScope TestEnvironment {
            Mock Invoke-WebRequest {
                $exception = [System.Net.WebException]::new('The remote server returned an error: (429) Too Many Requests.')
                throw $exception
            }

            $caught = $null
            try { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET } catch { $caught = $_ }

            $caught.Exception -is [System.Net.WebException] | Should-BeTrue
            $caught.Exception.Message | Should-MatchString '429'
        }
    }

    It 'adds TLS 1.2 to the enabled protocols on the Desktop edition without removing any' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
        InModuleScope TestEnvironment {
            $before = [System.Net.ServicePointManager]::SecurityProtocol
            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET
            $after = [System.Net.ServicePointManager]::SecurityProtocol

            ($after -band [System.Net.SecurityProtocolType]::Tls12) -eq [System.Net.SecurityProtocolType]::Tls12 | Should-BeTrue
            ($after -band $before) -eq $before | Should-BeTrue
        }
    }
}
