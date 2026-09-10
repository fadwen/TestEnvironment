#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Batching is what makes AD parity practical, and it fails in ways a single request cannot.

    The three that matter are all pinned below. A batch returns 200 even when every request
    inside it failed, so a caller checking only the outer result sees success while nothing was
    created. Responses come back in arbitrary order, so correlating by position rather than by
    id silently attributes results to the wrong objects. And a throttled or lagging individual
    request has to be retried on its own, not by resending the whole chunk, or the nineteen
    that succeeded alongside it are created twice.

    The 404 case is a regression: without it, placing 305 users into an administrative unit
    landed 72 and reported the other 233 as failures.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-EntraBatch' -Tag 'Unit' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:TestConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }
            $script:SentBatches = [System.Collections.Generic.List[object]]::new()
            Mock Start-Sleep { }
        }
    }

    Context 'Chunking' {

        It 'sends nothing at all for an empty request list' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest { throw 'should not be called' }

                $result = @(Invoke-EntraBatch -Request @() -Connection $script:TestConnection)
                $result.Count | Should-Be 0
                Should-NotInvoke Invoke-EntraRequest
            }
        }

        It 'sends one batch for twenty requests' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    $script:SentBatches.Add($Body.requests)
                    [PSCustomObject]@{ responses = @($Body.requests | ForEach-Object {
                                [PSCustomObject]@{ id = $_.id; status = 201; body = [PSCustomObject]@{ id = 'x' } } }) }
                }

                $requests = 1..20 | ForEach-Object { [PSCustomObject]@{ Reference = "r$_"; Method = 'POST'; Url = '/users'; Body = @{} } }
                $result = @(Invoke-EntraBatch -Request $requests -Connection $script:TestConnection)

                $script:SentBatches.Count | Should-Be 1
                $result.Count | Should-Be 20
            }
        }

        It 'splits twenty-one requests into two batches, because Graph refuses more than twenty' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    $script:SentBatches.Add($Body.requests)
                    [PSCustomObject]@{ responses = @($Body.requests | ForEach-Object {
                                [PSCustomObject]@{ id = $_.id; status = 201; body = [PSCustomObject]@{ id = 'x' } } }) }
                }

                $requests = 1..21 | ForEach-Object { [PSCustomObject]@{ Reference = "r$_"; Method = 'POST'; Url = '/users'; Body = @{} } }
                $result = @(Invoke-EntraBatch -Request $requests -Connection $script:TestConnection)

                $script:SentBatches.Count | Should-Be 2
                @($script:SentBatches[0]).Count | Should-Be 20
                @($script:SentBatches[1]).Count | Should-Be 1
                $result.Count | Should-Be 21
            }
        }

        It 'attaches a Content-Type header to any request carrying a body' {
            InModuleScope TestEnvironment {
                # Without it Graph rejects the inner request rather than the batch, so the
                # failure reads like a bad payload.
                Mock Invoke-EntraRequest {
                    $script:SentBatches.Add($Body.requests)
                    [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 201; body = $null }) }
                }

                Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                    [PSCustomObject]@{ Reference = 'r1'; Method = 'POST'; Url = '/users'; Body = @{ a = 1 } }) | Out-Null

                @($script:SentBatches[0])[0].headers['Content-Type'] | Should-Be 'application/json'
            }
        }
    }

    Context 'Correlation' {

        It 'matches responses to requests by id, not by position' {
            InModuleScope TestEnvironment {
                # Graph returns responses in arbitrary order. Correlating by position would
                # silently attribute each result to the wrong object.
                Mock Invoke-EntraRequest {
                    [PSCustomObject]@{ responses = @(
                            [PSCustomObject]@{ id = '2'; status = 201; body = [PSCustomObject]@{ id = 'third' } }
                            [PSCustomObject]@{ id = '0'; status = 201; body = [PSCustomObject]@{ id = 'first' } }
                            [PSCustomObject]@{ id = '1'; status = 201; body = [PSCustomObject]@{ id = 'second' } }
                        ) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                        [PSCustomObject]@{ Reference = 'alpha'; Method = 'POST'; Url = '/users' }
                        [PSCustomObject]@{ Reference = 'beta'; Method = 'POST'; Url = '/users' }
                        [PSCustomObject]@{ Reference = 'gamma'; Method = 'POST'; Url = '/users' }
                    ))

                ($result | Where-Object Reference -eq 'alpha').Body.id | Should-Be 'first'
                ($result | Where-Object Reference -eq 'beta').Body.id | Should-Be 'second'
                ($result | Where-Object Reference -eq 'gamma').Body.id | Should-Be 'third'
            }
        }

        It 'returns exactly one result per request sent' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    [PSCustomObject]@{ responses = @($Body.requests | ForEach-Object {
                                [PSCustomObject]@{ id = $_.id; status = 400; body = [PSCustomObject]@{ error = [PSCustomObject]@{ code = 'Bad'; message = 'no' } } } }) }
                }

                $requests = 1..5 | ForEach-Object { [PSCustomObject]@{ Reference = "r$_"; Method = 'POST'; Url = '/users' } }
                $result = @(Invoke-EntraBatch -Request $requests -Connection $script:TestConnection)

                # Failures are reported, never dropped, so a caller counting results always
                # gets one per request.
                $result.Count | Should-Be 5
                @($result | Where-Object { -not $_.Success }).Count | Should-Be 5
            }
        }
    }

    Context 'Per-response status' {

        It 'reports a failure inside an otherwise successful batch' {
            InModuleScope TestEnvironment {
                # The outer call returns 200 even when a request inside it failed, so a caller
                # checking only the outer result sees success while nothing was created.
                Mock Invoke-EntraRequest {
                    [PSCustomObject]@{ responses = @(
                            [PSCustomObject]@{ id = '0'; status = 201; body = [PSCustomObject]@{ id = 'ok' } }
                            [PSCustomObject]@{ id = '1'; status = 400; body = [PSCustomObject]@{ error = [PSCustomObject]@{ code = 'Request_BadRequest'; message = 'Already exists' } } }
                        ) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                        [PSCustomObject]@{ Reference = 'good'; Method = 'POST'; Url = '/users' }
                        [PSCustomObject]@{ Reference = 'bad'; Method = 'POST'; Url = '/users' }
                    ))

                ($result | Where-Object Reference -eq 'good').Success | Should-BeTrue
                ($result | Where-Object Reference -eq 'bad').Success | Should-BeFalse
                ($result | Where-Object Reference -eq 'bad').Error | Should-MatchString 'Request_BadRequest.*Already exists'
            }
        }
    }

    Context 'Retry' {

        It 'retries only the throttled request, not the whole chunk' {
            InModuleScope TestEnvironment {
                # Resending the chunk would create the requests that already succeeded a
                # second time.
                $script:Pass = 0
                Mock Invoke-EntraRequest {
                    $script:Pass++
                    $script:SentBatches.Add($Body.requests)
                    if ($script:Pass -eq 1) {
                        return [PSCustomObject]@{ responses = @(
                                [PSCustomObject]@{ id = '0'; status = 201; body = [PSCustomObject]@{ id = 'ok' } }
                                [PSCustomObject]@{ id = '1'; status = 429; body = $null }
                            ) }
                    }
                    return [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 201; body = [PSCustomObject]@{ id = 'later' } }) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                        [PSCustomObject]@{ Reference = 'first'; Method = 'POST'; Url = '/users' }
                        [PSCustomObject]@{ Reference = 'throttled'; Method = 'POST'; Url = '/users' }
                    ))

                # The second batch carried only the throttled request.
                @($script:SentBatches[1]).Count | Should-Be 1
                $result.Count | Should-Be 2
                @($result | Where-Object Success).Count | Should-Be 2
            }
        }

        It 'does not retry a 404 unless asked to' {
            InModuleScope TestEnvironment {
                $script:Pass = 0
                Mock Invoke-EntraRequest {
                    $script:Pass++
                    [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 404; body = $null }) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                        [PSCustomObject]@{ Reference = 'r1'; Method = 'DELETE'; Url = '/users/1' }))

                $script:Pass | Should-Be 1
                $result[0].Success | Should-BeFalse
            }
        }

        It 'retries a 404 when told to, because a reference can outrun replication' {
            InModuleScope TestEnvironment {
                # The regression: placing 305 users into an administrative unit landed 72 and
                # reported the other 233 as failures, because the reference named objects the
                # handling replica had not seen yet.
                $script:Pass = 0
                Mock Invoke-EntraRequest {
                    $script:Pass++
                    if ($script:Pass -lt 3) {
                        return [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 404; body = $null }) }
                    }
                    return [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 204; body = $null }) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -RetryOnNotFound -Request @(
                        [PSCustomObject]@{ Reference = 'r1'; Method = 'POST'; Url = '/directory/administrativeUnits/x/members/$ref' }))

                $script:Pass | Should-Be 3
                $result[0].Success | Should-BeTrue
            }
        }

        It 'retries every request when the batch call itself fails' {
            InModuleScope TestEnvironment {
                # Nothing inside it ran, so each request is retryable rather than failed.
                $script:Pass = 0
                Mock Invoke-EntraRequest {
                    $script:Pass++
                    if ($script:Pass -eq 1) { throw 'gateway exploded' }
                    [PSCustomObject]@{ responses = @($Body.requests | ForEach-Object {
                                [PSCustomObject]@{ id = $_.id; status = 201; body = [PSCustomObject]@{ id = 'ok' } } }) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -Request @(
                        [PSCustomObject]@{ Reference = 'a'; Method = 'POST'; Url = '/users' }
                        [PSCustomObject]@{ Reference = 'b'; Method = 'POST'; Url = '/users' }
                    ))

                $result.Count | Should-Be 2
                @($result | Where-Object Success).Count | Should-Be 2
            }
        }

        It 'gives up after MaxRetry passes and reports the survivors as failures' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    [PSCustomObject]@{ responses = @([PSCustomObject]@{ id = '0'; status = 429; body = $null }) }
                }

                $result = @(Invoke-EntraBatch -Connection $script:TestConnection -MaxRetry 2 -WarningAction SilentlyContinue -Request @(
                        [PSCustomObject]@{ Reference = 'r1'; Method = 'POST'; Url = '/users' }))

                $result.Count | Should-Be 1
                $result[0].Success | Should-BeFalse
                $result[0].Error | Should-MatchString 'Still failing'
            }
        }
    }
}
