#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The single network path. Invoke-WebRequest is mocked; nothing reaches OneLogin.

    The encoding handling follows the HTTP encoding invariant in CLAUDE.md and these pin it through
    this provider's own function, both directions: a body goes out as UTF-8 bytes, and a response is
    decoded from its raw bytes as UTF-8 whatever charset it declares.

    The rest pins what was learned against a live account: a list pages by limit and page and says
    how many pages in Total-Pages; a JSON array is one object to Windows PowerShell's
    ConvertFrom-Json, which once would have ended pagination after the first page; a 401 is a
    token to renew once; a 429 is waited out briefly and reported when the wait is long.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    # Imported once per run, not once per file. CI runs the suite shuffled, so state one file
    # leaves behind for another fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Invoke-OneLoginRequest' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com' }
            Mock Get-OneLoginAccessToken { 'test-token' }
            Mock Start-Sleep { }

            # What Invoke-WebRequest hands back for a JSON body. Content is decoded as ISO-8859-1 on
            # purpose - 28591, by number because .NET Framework has no Latin1 property - which is
            # what Windows PowerShell does when a charset is missing, so only the raw stream is right.
            $script:Respond = {
                param([string]$Json, [hashtable]$Headers = @{})
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
                $all = @{ 'Content-Type' = 'application/json' }
                foreach ($key in $Headers.Keys) { $all[$key] = $Headers[$key] }
                [PSCustomObject]@{
                    StatusCode       = 200
                    Content          = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
                    Headers          = $all
                    RawContentStream = New-Object System.IO.MemoryStream(, $bytes)
                }
            }
            # A failed response, the way PowerShell 7 hands one over under -SkipHttpErrorCheck.
            $script:Fail = {
                param([int]$Status, [string]$Json, [hashtable]$Headers = @{})
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
                [PSCustomObject]@{
                    StatusCode       = $Status
                    Content          = $Json
                    Headers          = $Headers
                    RawContentStream = New-Object System.IO.MemoryStream(, $bytes)
                }
            }
        }
    }

    Context 'Addressing' {

        It 'puts a relative path below /api/2 on the account host, and an absolute one on the host itself' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":1}' }
                $null = Invoke-OneLoginRequest -Method GET -Path 'roles/5' -Connection $script:Connection
                $null = Invoke-OneLoginRequest -Method GET -Path '/auth/rate_limit' -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://contoso.onelogin.com/api/2/roles/5' }
                Should-Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://contoso.onelogin.com/auth/rate_limit' }
            }
        }

        It 'sends the bearer token and escapes the query' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '[]' }
                $null = Invoke-OneLoginRequest -Method GET -Path 'users' -Query @{ 'custom_attributes.zztest_seed_tag' = 'ZZ-TEST-seed'; fields = 'id,username' } -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $Headers.Authorization -eq 'Bearer test-token' -and
                    $Uri -eq 'https://contoso.onelogin.com/api/2/users?custom_attributes.zztest_seed_tag=ZZ-TEST-seed&fields=id%2Cusername'
                }
            }
        }
    }

    Context 'Encoding' {

        It 'sends a body as UTF-8 bytes with an explicit charset, never as a string' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":1}' }
                $name = 'Jos' + [char]0x00E9 + ' Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0x59DC + [char]0xD842 + [char]0xDFB7

                $null = Invoke-OneLoginRequest -Method POST -Path 'users' -Body @{ firstname = $name } -Connection $script:Connection

                Should-Invoke Invoke-WebRequest -ParameterFilter { $Body -is [byte[]] -and $ContentType -eq 'application/json; charset=utf-8' }
                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $sent = ([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).firstname
                    [string]::Equals($sent, ('Jos' + [char]0x00E9 + ' Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0x59DC + [char]0xD842 + [char]0xDFB7), [StringComparison]::Ordinal)
                }
            }
        }

        It 'decodes a response from its raw bytes as UTF-8, on a single object and on every page' {
            InModuleScope TestEnvironment {
                $name = 'Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0xD842 + [char]0xDFB7 + [char]0x7530
                Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*users/1' } { & $script:Respond ('{"firstname":"' + $name + '"}') }
                Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*users?*' } { & $script:Respond ('[{"id":1,"firstname":"' + $name + '"}]') }

                $one = Invoke-OneLoginRequest -Method GET -Path 'users/1' -Connection $script:Connection
                $many = @(Invoke-OneLoginRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection)

                # Ordinal, never -eq: PowerShell compares strings linguistically and would call a
                # decomposed and a precomposed name equal.
                [string]::Equals($one.firstname, $name, [StringComparison]::Ordinal) | Should-BeTrue
                [string]::Equals($many[0].firstname, $name, [StringComparison]::Ordinal) | Should-BeTrue
            }
        }

        It 'passes a pre-serialised JSON array through untouched' {
            # The role endpoints take a bare array of ids, and a one-element array piped to
            # ConvertTo-Json becomes a bare number; the steps serialise it themselves.
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '[{"id":7}]' }
                $null = Invoke-OneLoginRequest -Method POST -Path 'roles/1/users' -Body '[7]' -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter { [System.Text.Encoding]::UTF8.GetString($Body) -eq '[7]' }
            }
        }
    }

    Context 'Pagination' {

        It 'asks page after page until a page comes back short, and emits every item' {
            InModuleScope TestEnvironment {
                $script:OneLoginPageSize = 2
                try {
                    Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*page=1*' } { & $script:Respond '[{"id":1},{"id":2}]' }
                    Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*page=2*' } { & $script:Respond '[{"id":3}]' }

                    @(Invoke-OneLoginRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection).id | Should-BeCollection @(1, 2, 3)
                    Should-Invoke Invoke-WebRequest -Times 2 -Exactly
                    Should-Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*limit=2&page=1' }
                }
                finally { $script:OneLoginPageSize = 100 }
            }
        }

        It 'stops at the last page Total-Pages names even when that page is full' {
            InModuleScope TestEnvironment {
                $script:OneLoginPageSize = 2
                try {
                    Mock Invoke-WebRequest { & $script:Respond '[{"id":1},{"id":2}]' @{ 'Total-Pages' = '1' } }
                    @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $script:Connection) | Should-BeCollection -Count 2
                    Should-Invoke Invoke-WebRequest -Times 1 -Exactly
                }
                finally { $script:OneLoginPageSize = 100 }
            }
        }

        It 'emits items one by one, so a pipeline filter selects a single item' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '[{"id":1,"name":"ZZ-TEST-All Staff"},{"id":2,"name":"Default"}]' }
                $match = @(Invoke-OneLoginRequest -Method GET -Path 'roles' -Paginate -Connection $script:Connection | Where-Object name -eq 'Default')
                $match | Should-BeCollection -Count 1
                $match[0].id | Should-Be 2
            }
        }

        It 'returns nothing for an empty list or an empty body' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '[]' }
                @(Invoke-OneLoginRequest -Method GET -Path 'groups' -Paginate -Connection $script:Connection) | Should-BeCollection -Count 0
                Mock Invoke-WebRequest { & $script:Respond '' }
                Invoke-OneLoginRequest -Method DELETE -Path 'groups/1' -Connection $script:Connection | Should-BeNull
            }
        }
    }

    Context 'Errors, renewal and backoff' {

        It 'returns nothing for a status the caller asked to ignore' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 404 '{"status":404,"error":"NotFoundError","description":"Resource not found"}' }
                Invoke-OneLoginRequest -Method DELETE -Path 'roles/1' -IgnoreStatus 404 -Connection $script:Connection | Should-BeNull
            }
        }

        It 'throws with the status, the error name and OneLogin''s message for anything else' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 422 '{"name":"UnprocessableEntityError","message":"Validation failed: Username must be unique","statusCode":422}' }
                { Invoke-OneLoginRequest -Method POST -Path 'users' -Body @{ username = 'x' } -Connection $script:Connection } |
                    Should-Throw -ExceptionMessage '*HTTP 422: UnprocessableEntityError: Validation failed: Username must be unique*'
            }
        }

        It 'renews the token once on a 401 and repeats the call' {
            InModuleScope TestEnvironment {
                $script:Calls = 0
                Mock Invoke-WebRequest {
                    $script:Calls++
                    if ($script:Calls -eq 1) { return (& $script:Fail 401 '{"name":"UnauthorizedError","message":"Unauthorized","statusCode":401}') }
                    & $script:Respond '{"id":1}'
                }
                $script:Connection.AccessToken = 'stale'
                (Invoke-OneLoginRequest -Method GET -Path 'roles/1' -Connection $script:Connection).id | Should-Be 1
                $script:Connection.AccessToken | Should-BeNull
                Should-Invoke Invoke-WebRequest -Times 2 -Exactly
            }
        }

        It 'does not renew forever: a second 401 is thrown' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 401 '{"name":"UnauthorizedError","message":"Unauthorized","statusCode":401}' }
                { Invoke-OneLoginRequest -Method GET -Path 'roles' -Connection $script:Connection } | Should-Throw -ExceptionMessage '*HTTP 401*'
                Should-Invoke Invoke-WebRequest -Times 2 -Exactly
            }
        }

        It 'waits out a short 429 and retries' {
            InModuleScope TestEnvironment {
                $script:Calls = 0
                Mock Invoke-WebRequest {
                    $script:Calls++
                    if ($script:Calls -eq 1) { return (& $script:Fail 429 '{"statusCode":429,"name":"TooManyRequests","message":"Rate limit"}' @{ 'Retry-After' = '7' }) }
                    & $script:Respond '{"id":1}'
                }
                (Invoke-OneLoginRequest -Method GET -Path 'roles/1' -Connection $script:Connection -WarningAction SilentlyContinue).id | Should-Be 1
                Should-Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
            }
        }

        It 'reports rather than sleeps through a reset that is far away' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 429 '{"statusCode":429,"message":"Rate limit"}' @{ 'X-RateLimit-Reset' = '1800' } }
                { Invoke-OneLoginRequest -Method GET -Path 'roles' -Connection $script:Connection } | Should-Throw -ExceptionMessage '*resets in 1800 seconds*'
                Should-NotInvoke Start-Sleep
            }
        }

        It 'reduces an HTML error page to its status' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 400 '<!DOCTYPE html><html><body>400: BAD REQUEST</body></html>' }
                { Invoke-OneLoginRequest -Method GET -Path 'privileges' -Connection $script:Connection } |
                    Should-Throw -ExceptionMessage '*HTTP 400: OneLogin answered with an HTML error page*'
            }
        }
    }
}
