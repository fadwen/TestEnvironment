#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every Graph call in the module goes through this function, so a defect here is a defect
    everywhere. The cases below are the ones that actually bite.

    The pagination loop guard is a regression: Graph will return an @odata.nextLink pointing
    at the page just fetched, and following it without comparison spins forever while looking
    exactly like a slow tenant.

    The retry cases matter because two different replication failures are reported with two
    different status codes - 404 for an object not yet addressable, and 400 for a service
    principal whose application "does not reference a valid application object". Only the
    first is inferable from the status, which is why the second exists as a separate switch.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-EntraRequest' -Tag 'Unit' {

    BeforeEach {
        InModuleScope TestEnvironment {
            # A connection that never triggers a token request: the expiry is far enough out
            # that Get-EntraAccessToken returns the cached value untouched.
            $script:TestConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                Certificate    = $null
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }
        }
    }

    Context 'Request construction' {

        It 'builds the URI from the base, the API version and the path' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{"id":"1"}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                    $Uri -eq 'https://graph.microsoft.com/v1.0/users'
                }
            }
        }

        It 'uses the beta endpoint when asked' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -ApiVersion beta -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                    $Uri -eq 'https://graph.microsoft.com/beta/users'
                }
            }
        }

        It 'sends the bearer token' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                    $Headers['Authorization'] -eq 'Bearer test-token'
                }
            }
        }

        It 'sends ConsistencyLevel only when asked, since Graph rejects advanced queries without it' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection | Out-Null
                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter { -not $Headers.ContainsKey('ConsistencyLevel') }

                Invoke-EntraRequest -Method GET -Path '/users' -ConsistencyLevel -Connection $script:TestConnection | Out-Null
                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Headers['ConsistencyLevel'] -eq 'eventual' }
            }
        }

        It 'leaves the dollar sign on OData parameters unescaped, and escapes the values' {
            InModuleScope TestEnvironment {
                # The URI is captured rather than matched inside a ParameterFilter, so a
                # failure prints the URI that was actually built instead of only reporting
                # that nothing matched.
                $script:CapturedUri = $null
                Mock Invoke-WebRequest {
                    $script:CapturedUri = $Uri
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection `
                    -Query @{ '$filter' = "startswith(displayName,'A B')" } | Out-Null

                # AbsoluteUri, not ToString(). Invoke-WebRequest types -Uri as [uri], and
                # Uri.ToString() renders the value back in its UNESCAPED form - so asserting
                # on it reports a space where the request really carries %20, and would fail
                # against correctly escaped output.
                $absolute = ([uri]$script:CapturedUri).AbsoluteUri

                # Escaping the leading dollar to %24 is accepted by Graph and makes every
                # verbose trace unreadable, so it is deliberately left alone.
                $absolute | Should-MatchString '\?\$filter='
                $absolute | Should-NotMatchString '%24filter'
                # The value is escaped, so the space inside the filter cannot break the URI.
                $absolute | Should-MatchString 'A%20B'
            }
        }

        It 'omits query parameters with no value rather than sending them empty' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection `
                    -Query @{ '$select' = 'id'; '$filter' = '' } | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -notlike '*filter*' }
            }
        }

        It 'sends the body as UTF-8 bytes so accented names survive' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                $name = 'Zo' + [char]0x00EB + ' M' + [char]0x00FC + 'ller'
                Invoke-EntraRequest -Method POST -Path '/users' -Connection $script:TestConnection `
                    -Body @{ displayName = $name } | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                    # Decoding the bytes back as UTF-8 must yield the original name. On
                    # Windows PowerShell an unencoded body would arrive as question marks.
                    ([System.Text.Encoding]::UTF8.GetString($Body)) -like "*$name*"
                }
            }
        }

        It 'sends a string body unchanged rather than re-serialising it' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{}'; Headers = @{} }
                }

                Invoke-EntraRequest -Method POST -Path '/users' -Connection $script:TestConnection `
                    -Body '{"already":"json"}' | Out-Null

                Should-Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                    ([System.Text.Encoding]::UTF8.GetString($Body)) -eq '{"already":"json"}'
                }
            }
        }
    }

    Context 'Response decoding' {

        It 'decodes the raw stream as UTF-8 rather than trusting the declared charset' {
            InModuleScope TestEnvironment {
                $name = 'Tom' + [char]0x00E1 + 's'
                $json = "{`"displayName`":`"$name`"}"
                $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($json))

                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $stream; Content = 'ignored'; Headers = @{} }
                }

                $result = Invoke-EntraRequest -Method GET -Path '/users/1' -Connection $script:TestConnection
                $result.displayName | Should-Be $name
            }
        }

        It 'returns null for an empty response body' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ RawContentStream = $null; Content = ''; Headers = @{} }
                }

                $result = Invoke-EntraRequest -Method DELETE -Path '/users/1' -Connection $script:TestConnection
                $result | Should-BeNull
            }
        }
    }

    Context 'Pagination' {

        It 'follows @odata.nextLink and returns every page' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $body = if ($script:CallCount -eq 1) {
                        '{"value":[{"id":"1"},{"id":"2"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=abc"}'
                    }
                    else {
                        '{"value":[{"id":"3"}]}'
                    }
                    [PSCustomObject]@{
                        RawContentStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($body))
                        Content          = $body
                        Headers          = @{}
                    }
                }

                $result = @(Invoke-EntraRequest -Method GET -Path '/users' -Paginate -Connection $script:TestConnection)

                $result.Count | Should-Be 3
                @($result.id) | Should-BeCollection @('1', '2', '3')
                $script:CallCount | Should-Be 2
            }
        }

        It 'stops when nextLink points at the page just fetched' {
            InModuleScope TestEnvironment {
                # The regression. Graph really does return a self-referential nextLink, and
                # following it is an infinite loop that presents as a hang.
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $body = '{"value":[{"id":"1"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users"}'
                    [PSCustomObject]@{
                        RawContentStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($body))
                        Content          = $body
                        Headers          = @{}
                    }
                }

                $result = @(Invoke-EntraRequest -Method GET -Path '/users' -Paginate -Connection $script:TestConnection)

                $script:CallCount | Should-Be 1
                $result.Count | Should-Be 1
            }
        }

        It 'returns an empty array rather than null when there is nothing to page' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    # Built inside the mock: a variable from the enclosing It block is not in
                    # scope here, and would arrive as null.
                    $emptyPage = '{"value":[]}'
                    [PSCustomObject]@{
                        RawContentStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($emptyPage))
                        Content          = $emptyPage
                        Headers          = @{}
                    }
                }

                $result = @(Invoke-EntraRequest -Method GET -Path '/users' -Paginate -Connection $script:TestConnection)
                $result.Count | Should-Be 0
            }
        }
    }

    Context 'Retry policy' {

        BeforeEach {
            InModuleScope TestEnvironment {
                # Nothing here should actually wait. A retry test that sleeps for real turns a
                # fast suite into a slow one for no extra coverage.
                Mock Start-Sleep { }
            }
        }

        It 'does not retry a 403, because a permission does not appear by waiting' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $response = [PSCustomObject]@{ StatusCode = 403 }
                    $exception = [System.Exception]::new('Forbidden')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                }

                { Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection } | Should-Throw
                $script:CallCount | Should-Be 1
            }
        }

        It 'does not retry a 404 unless asked to' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $response = [PSCustomObject]@{ StatusCode = 404 }
                    $exception = [System.Exception]::new('Not Found')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                }

                { Invoke-EntraRequest -Method GET -Path '/users/1' -Connection $script:TestConnection } | Should-Throw
                $script:CallCount | Should-Be 1
            }
        }

        It 'retries a 404 when told to, because replication lags a create' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    if ($script:CallCount -lt 3) {
                        $response = [PSCustomObject]@{ StatusCode = 404 }
                        $exception = [System.Exception]::new('Not Found')
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                        throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                    }
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{"id":"1"}'; Headers = @{} }
                }

                $result = Invoke-EntraRequest -Method DELETE -Path '/users/1' -RetryOnNotFound -Connection $script:TestConnection
                $script:CallCount | Should-Be 3
                $result.id | Should-Be '1'
            }
        }

        It 'retries a 400 whose message matches, which is how a lagging service principal fails' {
            InModuleScope TestEnvironment {
                # Not inferable from the status code: Graph reports this replication failure
                # as 400, indistinguishable from a genuinely malformed request.
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    if ($script:CallCount -lt 2) {
                        $response = [PSCustomObject]@{ StatusCode = 400 }
                        $exception = [System.Exception]::new('Bad Request')
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                        $record = [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                            '{"error":{"code":"Request_BadRequest","message":"The appId does not reference a valid application object."}}')
                        throw $record
                    }
                    [PSCustomObject]@{ RawContentStream = $null; Content = '{"id":"sp1"}'; Headers = @{} }
                }

                $result = Invoke-EntraRequest -Method POST -Path '/servicePrincipals' -Connection $script:TestConnection `
                    -RetryOnErrorMatch 'does not reference a valid application object' -Body @{ appId = 'x' }

                $script:CallCount | Should-Be 2
                $result.id | Should-Be 'sp1'
            }
        }

        It 'does not retry a 400 whose message does not match' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = [System.Exception]::new('Bad Request')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                        '{"error":{"code":"Request_BadRequest","message":"Something else entirely."}}')
                    throw $record
                }

                { Invoke-EntraRequest -Method POST -Path '/servicePrincipals' -Connection $script:TestConnection `
                        -RetryOnErrorMatch 'does not reference a valid application object' -Body @{ appId = 'x' } } | Should-Throw

                $script:CallCount | Should-Be 1
            }
        }

        It 'gives up after MaxRetry attempts' {
            InModuleScope TestEnvironment {
                $script:CallCount = 0
                Mock Invoke-WebRequest {
                    $script:CallCount++
                    $response = [PSCustomObject]@{ StatusCode = 503 }
                    $exception = [System.Exception]::new('Service Unavailable')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                }

                { Invoke-EntraRequest -Method GET -Path '/users' -MaxRetry 3 -Connection $script:TestConnection } | Should-Throw
                $script:CallCount | Should-Be 3
            }
        }
    }

    Context 'Error reporting' {

        It 'surfaces the Graph error code and message rather than the bare HTTP status' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 403 }
                    $exception = [System.Exception]::new('Forbidden')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                        '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}')
                    throw $record
                }

                { Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection } |
                    Should-Throw -ExceptionMessage '*Authorization_RequestDenied*Insufficient privileges*'
            }
        }

        It 'includes the request id, which is the only handle Microsoft support has' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = [System.Exception]::new('Bad Request')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                        '{"error":{"code":"Request_BadRequest","message":"Bad.","innerError":{"request-id":"abc-123"}}}')
                    throw $record
                }

                { Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection } |
                    Should-Throw -ExceptionMessage '*abc-123*'
            }
        }

        It 'sets the inner exception rather than stringifying it into the message' {
            InModuleScope TestEnvironment {
                # The New-Object(string, exception) trap: a concatenation written inline binds
                # as one array argument, producing a message with the inner exception's whole
                # stack trace in it and no InnerException set at all.
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = [System.Exception]::new('The original failure')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                }

                $caught = $null
                try { Invoke-EntraRequest -Method GET -Path '/users' -Connection $script:TestConnection }
                catch { $caught = $_.Exception }

                $caught | Should-NotBeNull
                $caught.InnerException | Should-NotBeNull
                $caught.InnerException.Message | Should-Be 'The original failure'
            }
        }

        It 'names the method and path in the failure' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    $response = [PSCustomObject]@{ StatusCode = 400 }
                    $exception = [System.Exception]::new('Bad')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
                    throw [System.Management.Automation.ErrorRecord]::new($exception, 'E', 'NotSpecified', $null)
                }

                { Invoke-EntraRequest -Method PATCH -Path '/groups/xyz' -Connection $script:TestConnection } |
                    Should-Throw -ExceptionMessage '*PATCH*/groups/xyz*'
            }
        }
    }
}
