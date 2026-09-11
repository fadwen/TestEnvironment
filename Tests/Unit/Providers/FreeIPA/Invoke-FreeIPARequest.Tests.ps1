#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every FreeIPA call goes through one function, and what it has to get right is the shape
    of JSON-RPC: arguments as a list even when there is one, the API version in the options,
    success and failure both arriving as HTTP 200 with the answer in the body, an expected
    failure named by the caller returning nothing rather than throwing, an expired session
    renewed exactly once, and a search unbounded so the server's two-second time limit cannot
    silently truncate three hundred users. The transport itself is mocked; nothing here
    reaches a server.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-FreeIPARequest' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ BaseUrl = 'https://ipa.example.com'; Username = 'svc'; Password = 'pw'; ApiVersion = '2.257'; Client = 'client' }
            $script:Sent = [System.Collections.Generic.List[object]]::new()
            Mock Send-FreeIPAHttpRequest {
                $script:Sent.Add(@{ Path = $Path; Json = $Json; Form = $Form })
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": {"result": {"uid": ["jnino"]}, "value": "jnino", "summary": null}, "error": null, "id": 0, "principal": "svc@EXAMPLE.COM", "version": "4.13.1"}' }
            }
        }
    }

    It 'sends the method, a list of arguments, the options and the API version as JSON-RPC' {
        InModuleScope TestEnvironment {
            $r = Invoke-FreeIPARequest -Method 'user_show' -Arguments 'jnino' -Options @{ all = $true } -Connection $script:Connection

            $r.result.uid | Should-Be 'jnino'
            $script:Sent[0].Path | Should-Be '/ipa/session/json'
            $payload = $script:Sent[0].Json | ConvertFrom-Json
            $payload.method | Should-Be 'user_show'
            # A single argument still travels as a JSON array, which is what the server parses.
            $script:Sent[0].Json | Should-MatchString '"params":\[\["jnino"\],\{'
            $payload.params[1].version | Should-Be '2.257'
            $payload.params[1].all | Should-BeTrue
        }
    }

    It 'unbounds a search and returns the entries rather than the envelope' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                $script:Sent.Add(@{ Json = $Json })
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": {"result": [{"uid": ["a"]}, {"uid": ["b"]}], "count": 2, "truncated": false}, "error": null}' }
            }

            $entries = @(Invoke-FreeIPARequest -Method 'user_find' -Options @{ userclass = 'ZZ-TEST-seed' } -Find -Connection $script:Connection)

            $entries.Count | Should-Be 2
            $payload = $script:Sent[0].Json | ConvertFrom-Json
            $payload.params[1].sizelimit | Should-Be 0
            $payload.params[1].timelimit | Should-Be 0
            $script:Sent[0].Json | Should-MatchString '"params":\[\[\],\{'
        }
    }

    It 'sends no limit at all under -NoLimit, for the searches that refuse one' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                $script:Sent.Add(@{ Json = $Json })
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": {"result": [{"cn": ["zz-test-contractors"]}], "count": 1, "truncated": false}, "error": null}' }
            }
            $entries = @(Invoke-FreeIPARequest -Method 'automember_find' -Options @{ type = 'group' } -Find -NoLimit -Connection $script:Connection)
            $entries.Count | Should-Be 1
            $payload = $script:Sent[0].Json | ConvertFrom-Json
            $payload.params[1].PSObject.Properties.Name | Should-NotContainCollection @('sizelimit')
            $payload.params[1].PSObject.Properties.Name | Should-NotContainCollection @('timelimit')
        }
    }

    It 'throws the error name, code and message when the body carries an error' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": null, "error": {"code": 4002, "message": "group with name \"zz-test-all-staff\" already exists", "name": "DuplicateEntry"}}' }
            }

            { Invoke-FreeIPARequest -Method 'group_add' -Arguments 'zz-test-all-staff' -Connection $script:Connection } |
                Should-Throw -ExceptionMessage '*group_add failed (DuplicateEntry 4002)*already exists*'
        }
    }

    It 'returns nothing for an error the caller named as expected' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": null, "error": {"code": 4001, "message": "nobody: user not found", "name": "NotFound"}}' }
            }

            $r = Invoke-FreeIPARequest -Method 'user_show' -Arguments 'nobody' -IgnoreError 'NotFound' -Connection $script:Connection
            $r | Should-BeNull
            { Invoke-FreeIPARequest -Method 'user_show' -Arguments 'nobody' -IgnoreError 'EmptyModlist' -Connection $script:Connection } | Should-Throw
        }
    }

    It 'renews an expired session once and repeats the call' {
        InModuleScope TestEnvironment {
            $script:Calls = 0
            Mock Send-FreeIPAHttpRequest {
                if ($Path -eq '/ipa/session/login_password') { return [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '' } }
                $script:Calls++
                if ($script:Calls -eq 1) { return [PSCustomObject]@{ StatusCode = 401; Headers = @{}; Body = 'Unauthorized' } }
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": {"summary": "pong"}, "error": null}' }
            }

            $r = Invoke-FreeIPARequest -Method 'ping' -Connection $script:Connection
            $r.summary | Should-Be 'pong'
            Should-Invoke Send-FreeIPAHttpRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/ipa/session/login_password' }
            Should-Invoke Send-FreeIPAHttpRequest -Times 2 -Exactly -ParameterFilter { $Path -eq '/ipa/session/json' }
        }
    }

    It 'gives up when the renewed session is refused too, rather than looping' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                if ($Path -eq '/ipa/session/login_password') { return [PSCustomObject]@{ StatusCode = 401; Headers = @{ 'X-IPA-Rejection-Reason' = 'invalid-password' }; Body = '' } }
                [PSCustomObject]@{ StatusCode = 401; Headers = @{}; Body = 'Unauthorized' }
            }

            { Invoke-FreeIPARequest -Method 'ping' -Connection $script:Connection } | Should-Throw -ExceptionMessage '*credential was rejected (invalid-password)*'
        }
    }

    It 'warns when the server truncated a listing' {
        InModuleScope TestEnvironment {
            Mock Send-FreeIPAHttpRequest {
                [PSCustomObject]@{ StatusCode = 200; Headers = @{}; Body = '{"result": {"result": [{"uid": ["a"]}], "count": 1, "truncated": true}, "error": null}' }
            }

            $entries = @(Invoke-FreeIPARequest -Method 'user_find' -Find -Connection $script:Connection -WarningVariable warnings -WarningAction SilentlyContinue)
            $entries.Count | Should-Be 1
            @($warnings | Where-Object { $_ -like '*truncated*' }).Count | Should-Be 1
        }
    }

    It 'drops null options and keeps the caller''s explicit limits' {
        InModuleScope TestEnvironment {
            $null = Invoke-FreeIPARequest -Method 'group_find' -Options @{ description = $null; sizelimit = 5 } -Find -Connection $script:Connection -WarningAction SilentlyContinue
            $payload = $script:Sent[0].Json | ConvertFrom-Json
            $payload.params[1].PSObject.Properties.Name | Should-NotContainCollection @('description')
            $payload.params[1].sizelimit | Should-Be 5
            $payload.params[1].timelimit | Should-Be 0
        }
    }
}
