#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one HTTP call. Windows PowerShell 5.1 corrupts non-ASCII text on the way out and on the
    way back, and PowerShell 7 hides both faults, so these pin the four things the helper exists
    for in terms that fail on either edition: the body reaches Invoke-WebRequest as UTF-8 bytes
    with the charset named, the response is decoded from its raw stream and not from .Content,
    the progress preference comes back whether the call threw or not, and a failed response
    reaches the caller as one shape on either edition - an integer status, a case-insensitive
    header table and the body in ErrorDetails - whichever way the running PowerShell handed it
    over, while a transport failure with no response propagates untouched.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
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
                $script:Sent = @{ Body = $Body; ContentType = $ContentType; Headers = $Headers; Method = $Method; Uri = $Uri; Bound = @($PSBoundParameters.Keys); SkipHttpErrorCheck = [bool]$SkipHttpErrorCheck; HttpVersion = $HttpVersion }
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

    It 'lets a transport failure with no response propagate untouched' {
        InModuleScope TestEnvironment {
            Mock Invoke-WebRequest {
                throw [System.Net.WebException]::new('The remote name could not be resolved: api.example.com')
            }

            $caught = $null
            try { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET } catch { $caught = $_ }

            $caught.Exception -is [System.Net.WebException] | Should-BeTrue
            $caught.Exception.Message | Should-MatchString 'could not be resolved'
            $caught.Exception.Response | Should-BeNull
        }
    }

    It 'turns the exception Windows PowerShell throws into the one error shape, reading the stream once' {
        InModuleScope TestEnvironment {
            # A hashtable, because the stream method below is a closure and a counter it
            # captures by value would be its own copy.
            $script:Reads = @{ Count = 0 }
            Mock Invoke-WebRequest {
                $body = [System.Text.Encoding]::UTF8.GetBytes('{"error":"José was refused"}')
                $reads = $script:Reads
                $response = [PSCustomObject]@{
                    # A plain number: .NET Framework's HttpStatusCode has no 429 member and
                    # refuses the cast, where a real response carries the unnamed value and
                    # Invoke-TestWebRequest reads it as an integer either way.
                    StatusCode        = 429
                    StatusDescription = 'Too Many Requests'
                    Headers           = @{ 'Retry-After' = '7'; 'X-Trace' = @('a', 'b') }
                }
                $response | Add-Member -MemberType ScriptMethod -Name GetResponseStream -Value { $reads.Count++; [System.IO.MemoryStream]::new($body) }.GetNewClosure()
                # A plain exception carrying the response as an added property, thrown as a
                # record: a real WebException's Response is read-only and cannot be overridden
                # by an added member, and Windows PowerShell rewraps a bare thrown exception
                # and loses the member on the way, where a thrown record keeps it.
                $exception = New-Object System.Exception('The remote server returned an error: (429) Too Many Requests.')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                throw (New-Object System.Management.Automation.ErrorRecord($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null))
            }

            $caught = $null
            try { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method POST -Body @{ a = 1 } } catch { $caught = $_ }

            $caught.Exception.Response.StatusCode | Should-Be 429
            $caught.Exception.Response.StatusCode -is [int] | Should-BeTrue
            $caught.Exception.Response.Headers['retry-after'] | Should-Be '7'
            $caught.Exception.Response.Headers['X-Trace'] | Should-Be 'a, b'
            $caught.ErrorDetails.Message | Should-Be '{"error":"José was refused"}'
            $caught.Exception.Message | Should-Be 'POST https://api.example.com/x answered HTTP 429 Too Many Requests'
            $caught.Exception.InnerException.Message | Should-MatchString 'The remote server returned an error'
            $caught.FullyQualifiedErrorId | Should-MatchString 'TestWebRequest.HTTP429'
            $script:Reads.Count | Should-Be 1
        }
    }

    It 'reads a record that already carries the body in ErrorDetails without touching a stream' {
        InModuleScope TestEnvironment {
            Mock Invoke-WebRequest {
                $response = [PSCustomObject]@{ StatusCode = 403; Headers = @{} }
                $exception = New-Object System.Exception('Forbidden')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                $record = New-Object System.Management.Automation.ErrorRecord($exception, 'x', 'InvalidOperation', $null)
                $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails('{"error":{"code":"Authorization_RequestDenied"}}')
                throw $record
            }

            $caught = $null
            try { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET } catch { $caught = $_ }

            $caught.Exception.Response.StatusCode | Should-Be 403
            $caught.ErrorDetails.Message | Should-MatchString 'Authorization_RequestDenied'
        }
    }

    It 'asks for the failed response back exactly where the cmdlet can, never HTTP/2, and reads a 4xx response as the same shape' {
        InModuleScope TestEnvironment {
            $real = @((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet).Parameters.Keys)
            $null = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET
            $script:Sent.SkipHttpErrorCheck | Should-Be ($real -contains 'SkipHttpErrorCheck')
            # Measured at no gain on a core-tier seed, so not asked for even where it exists.
            ([string]$script:Sent.HttpVersion) | Should-Be ''

            # PowerShell 7's way: the cmdlet returns the failed response and its body, decoded
            # from the raw bytes, becomes ErrorDetails. Taken on both editions, because a
            # response object with a failing status is the same object either way.
            $script:Respond = {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"detail":"Niño exists"}')
                [PSCustomObject]@{
                    StatusCode        = 400
                    StatusDescription = 'Bad Request'
                    Headers           = @{ 'Content-Type' = @('application/json') }
                    Content           = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
                    RawContentStream  = [System.IO.MemoryStream]::new($bytes)
                }
            }
            $caught = $null
            try { Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET } catch { $caught = $_ }

            $caught.Exception.Response.StatusCode | Should-Be 400
            $caught.Exception.Response.Headers['content-type'] | Should-Be 'application/json'
            $caught.ErrorDetails.Message | Should-Be '{"detail":"Niño exists"}'
            $caught.Exception.Message | Should-Be 'GET https://api.example.com/x answered HTTP 400 Bad Request'
        }
    }

    It 'flattens the response headers to one string per name, case-insensitively, on success too' {
        InModuleScope TestEnvironment {
            $script:Respond = {
                [PSCustomObject]@{
                    StatusCode       = 200
                    Headers          = @{ 'Link' = @('<https://a/1>; rel="self"', '<https://a/2>; rel="next"'); 'x-rate-limit-reset' = '1700000000' }
                    Content          = '{}'
                    RawContentStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes('{}'))
                }
            }
            $r = Invoke-TestWebRequest -Uri 'https://api.example.com/x' -Method GET

            $r.Headers['link'] | Should-Be '<https://a/1>; rel="self", <https://a/2>; rel="next"'
            $r.Headers['X-Rate-Limit-Reset'] | Should-Be '1700000000'
            $r.Headers['absent'] | Should-BeNull
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
