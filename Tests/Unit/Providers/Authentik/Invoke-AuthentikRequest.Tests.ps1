#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The request engine is the only Authentik code that touches the network, so these tests
    mock Invoke-WebRequest itself. What they pin is the Django REST Framework contract the
    rest of the provider relies on: page-number pagination with a 'next' that reaches zero,
    an error body that is either 'detail' or a map of field errors, and Retry-After on a 429.
    A regression in any of these shows up elsewhere as a seed that stops after the first
    hundred users, or an error that says 'Bad Request' where it should name the field.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-AuthentikRequest' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{
                BaseUrl             = 'https://auth.example.com'
                AuthorizationHeader = 'Bearer test-token'
            }
            Mock Start-Sleep { }
        }
    }

    Context 'Request construction' {

        It 'sends the bearer token and prefixes the path with /api/v3' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null } }

                $null = Invoke-AuthentikRequest -Method GET -Path '/core/users/me/' -Connection $script:Connection

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'https://auth.example.com/api/v3/core/users/me/' -and
                    $Headers['Authorization'] -eq 'Bearer test-token'
                }
            }
        }

        It 'drops empty query values and escapes the rest' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null } }

                $null = Invoke-AuthentikRequest -Method GET -Path '/core/groups/' -Connection $script:Connection `
                    -Query @{ search = 'ZZ TEST'; path = $null; empty = '' }

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'https://auth.example.com/api/v3/core/groups/?search=ZZ%20TEST'
                }
            }
        }

        It 'sends the body as UTF-8 bytes so accented data survives' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { [PSCustomObject]@{ Content = '{}'; Headers = @{}; RawContentStream = $null } }

                $accented = 'Z' + [string][char]0xFC + 'rich'
                $null = Invoke-AuthentikRequest -Method POST -Path '/core/groups/' -Connection $script:Connection -Body @{ name = $accented }

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                    $Body -is [byte[]] -and ([System.Text.Encoding]::UTF8.GetString($Body)).Contains($accented)
                }
            }
        }

        It 'decodes the response from raw UTF-8 bytes rather than trusting the charset' {
            InModuleScope TestEnvironment {
                $accented = 'Jos' + [string][char]0xE9
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"name":"' + $accented + '"}')
                Mock Invoke-WebRequest {
                    $stream = New-Object System.IO.MemoryStream(, $bytes)
                    # 28591 is ISO-8859-1, spelled by number because .NET Framework has no Latin1 property.
                    [PSCustomObject]@{ Content = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes); Headers = @{}; RawContentStream = $stream }
                }

                $result = Invoke-AuthentikRequest -Method GET -Path '/core/users/1/' -Connection $script:Connection
                $result.name | Should-Be $accented
            }
        }
    }

    Context 'Pagination' {

        It 'follows the page numbers until next is zero and flattens the results' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    $page = 1
                    if ($Uri -match 'page=(\d+)') { $page = [int]$Matches[1] }
                    $next = if ($page -lt 3) { $page + 1 } else { 0 }
                    $json = '{"pagination":{"next":' + $next + ',"current":' + $page + '},"results":[{"id":' + $page + '}]}'
                    [PSCustomObject]@{ Content = $json; Headers = @{}; RawContentStream = $null }
                }

                $result = @(Invoke-AuthentikRequest -Method GET -Path '/core/users/' -Connection $script:Connection -Paginate)

                $result.id | Should-BeCollection @(1, 2, 3)
                Should-Invoke Invoke-WebRequest -Times 3 -Exactly
                Should-Invoke Invoke-WebRequest -Times 3 -Exactly -ParameterFilter { $Uri -match 'page_size=100' }
            }
        }

        It 'stops when the server hands back the current page as the next one' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ Content = '{"pagination":{"next":1,"current":1},"results":[{"id":1}]}'; Headers = @{}; RawContentStream = $null }
                }

                $result = @(Invoke-AuthentikRequest -Method GET -Path '/core/users/' -Connection $script:Connection -Paginate)

                $result.Count | Should-Be 1
                Should-Invoke Invoke-WebRequest -Times 1 -Exactly
            }
        }

        It 'gives a caller that wraps the call in @() an empty array for an empty listing' {
            # The idiom every caller uses. A single item that is itself an empty array would
            # count as one here, which is how the bootstrap once refused to create an account
            # that did not exist.
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { [PSCustomObject]@{ Content = '{"pagination":{"next":0},"results":[]}'; Headers = @{}; RawContentStream = $null } }

                $result = @(Invoke-AuthentikRequest -Method GET -Path '/core/users/' -Connection $script:Connection -Paginate)
                $result.Count | Should-Be 0
            }
        }

        It 'refuses -Paginate against an endpoint that is not a listing' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { [PSCustomObject]@{ Content = '{"pk":1}'; Headers = @{}; RawContentStream = $null } }

                { Invoke-AuthentikRequest -Method GET -Path '/core/users/1/' -Connection $script:Connection -Paginate } |
                    Should-Throw -ExceptionMessage '*paginated listing*'
            }
        }
    }

    Context 'Error reporting' {

        BeforeEach {
            InModuleScope TestEnvironment {
                $script:Fail = {
                    param($status, $body)
                    $response = [PSCustomObject]@{ StatusCode = $status; Headers = @{} }
                    $exception = New-Object System.Exception('The remote server returned an error.')
                    $record = New-Object System.Management.Automation.ErrorRecord($exception, 'Failed', 'InvalidOperation', $null)
                    $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails($body)
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                    throw $record
                }
            }
        }

        It 'surfaces the detail message with the method, path and status' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 403 '{"detail":"You do not have permission to perform this action."}' }

                $thrown = $null
                try { $null = Invoke-AuthentikRequest -Method DELETE -Path '/core/users/7/' -Connection $script:Connection -MaxRetry 1 } catch { $thrown = $_ }

                $thrown.Exception.Message | Should-Be 'Authentik DELETE /core/users/7/ failed with HTTP 403: You do not have permission to perform this action.'
                $thrown.Exception.InnerException | Should-NotBeNull
            }
        }

        It 'names the field in a validation error' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 400 '{"slug":["application with this slug already exists."],"non_field_errors":["Bad combination."]}' }

                $thrown = $null
                try { $null = Invoke-AuthentikRequest -Method POST -Path '/core/applications/' -Connection $script:Connection -Body @{ x = 1 } -MaxRetry 1 } catch { $thrown = $_ }

                $thrown.Exception.Message | Should-MatchString 'slug: application with this slug already exists\.'
                $thrown.Exception.Message | Should-MatchString 'Bad combination\.'
            }
        }

        It 'retries a 429 honouring Retry-After and then succeeds' {
            InModuleScope TestEnvironment {
                $script:Attempts = 0
                Mock Invoke-WebRequest {
                    $script:Attempts++
                    if ($script:Attempts -eq 1) {
                        $response = [PSCustomObject]@{ StatusCode = 429; Headers = @{ 'Retry-After' = '3' } }
                        $exception = New-Object System.Exception('Too many requests.')
                        $record = New-Object System.Management.Automation.ErrorRecord($exception, 'Throttled', 'InvalidOperation', $null)
                        $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails('{"detail":"Request was throttled."}')
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
                        throw $record
                    }
                    [PSCustomObject]@{ Content = '{"ok":true}'; Headers = @{}; RawContentStream = $null }
                }

                $result = Invoke-AuthentikRequest -Method GET -Path '/core/users/me/' -Connection $script:Connection -WarningAction SilentlyContinue

                $result.ok | Should-BeTrue
                Should-Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
            }
        }

        It 'does not retry a 4xx that is not a throttle' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Fail 404 '{"detail":"Not found."}' }

                try { $null = Invoke-AuthentikRequest -Method GET -Path '/core/users/9/' -Connection $script:Connection } catch { $null = $_ }

                Should-Invoke Invoke-WebRequest -Times 1 -Exactly
                Should-NotInvoke Start-Sleep
            }
        }
    }
}
