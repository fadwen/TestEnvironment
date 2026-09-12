#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The single network path. Invoke-WebRequest is mocked; nothing reaches PingOne.

    The encoding handling follows the HTTP encoding invariant in CLAUDE.md, and these tests pin it,
    because this provider was first written without it and Windows PowerShell 5.1 corrupted every
    accented name it sent:

    - A body goes out as UTF-8 bytes. 5.1 sends a string body as ISO-8859-1 when no charset is
      named; against PingOne that stored a plain e-acute as U+FFFD, and a combining accent, a Han
      character and an astral pair as '?' each.
    - A response is decoded from its raw bytes as UTF-8, whatever charset it declares. 5.1 decodes
      by the declared charset and falls back to Latin-1; PingOne being correct today depends on a
      header this module does not control.

    One more pins a defect that shipped briefly while the provider was being built: the paginated
    result was returned wrapped in a unary comma, which foreach tolerates and a pipeline does not.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-PingOneRequest' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{
                EnvironmentId = '00000000-0000-4000-8000-000000000001'
                ApiHost       = 'api.pingone.com'
            }
            Mock Get-PingOneAccessToken { 'test-token' }

            # Builds what Invoke-WebRequest hands back for a JSON body. Content is decoded as
            # ISO-8859-1 on purpose - 28591, spelled by number because .NET Framework has no Latin1
            # property - which is what Windows PowerShell does when a charset is missing. Reading
            # Content would therefore be wrong, and only the raw stream is right.
            $script:Respond = {
                param([string]$Json)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
                [PSCustomObject]@{
                    Content          = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
                    Headers          = @{ 'Content-Type' = 'application/json' }
                    RawContentStream = New-Object System.IO.MemoryStream(, $bytes)
                }
            }
        }
    }

    Context 'Addressing' {

        It 'builds an environment-relative URI' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":"x"}' }
                $null = Invoke-PingOneRequest -Method GET -Path 'groups/abc' -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $Uri -eq 'https://api.pingone.com/v1/environments/00000000-0000-4000-8000-000000000001/groups/abc'
                }
            }
        }

        It 'treats a leading slash as absolute below /v1' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":"x"}' }
                $null = Invoke-PingOneRequest -Method GET -Path '/environments/abc' -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.pingone.com/v1/environments/abc' }
            }
        }

        It 'sends the bearer token, with basic parsing' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":"x"}' }
                $null = Invoke-PingOneRequest -Method GET -Path 'users' -Connection $script:Connection
                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $Headers.Authorization -eq 'Bearer test-token' -and $UseBasicParsing
                }
            }
        }
    }

    Context 'Encoding' {

        It 'sends a body as UTF-8 bytes with an explicit charset, never as a string' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"id":"x"}' }
                $name = 'Jos' + [char]0x00E9 + ' Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0x59DC + [char]0xD842 + [char]0xDFB7

                $null = Invoke-PingOneRequest -Method POST -Path 'users' -Body @{ name = $name } -Connection $script:Connection

                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $Body -is [byte[]] -and $ContentType -eq 'application/json; charset=utf-8'
                }
                Should-Invoke Invoke-WebRequest -ParameterFilter {
                    $sent = ([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).name
                    [string]::Equals($sent, ('Jos' + [char]0x00E9 + ' Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0x59DC + [char]0xD842 + [char]0xDFB7), [StringComparison]::Ordinal)
                }
            }
        }

        It 'decodes the response from its raw bytes as UTF-8 rather than trusting the declared charset' {
            InModuleScope TestEnvironment {
                $name = 'Jos' + [char]0x00E9 + ' Jos' + [char]0x0065 + [char]0x0301 + ' ' + [char]0x59DC + [char]0xD842 + [char]0xDFB7
                Mock Invoke-WebRequest { & $script:Respond ('{"name":"' + $name + '"}') }

                $result = Invoke-PingOneRequest -Method GET -Path 'users/1' -Connection $script:Connection

                # Ordinal, never -eq: PowerShell compares strings linguistically and would call a
                # decomposed and a precomposed name equal.
                [string]::Equals($result.name, $name, [StringComparison]::Ordinal) | Should-BeTrue
            }
        }

        It 'decodes every page of a paginated response the same way' {
            InModuleScope TestEnvironment {
                $name = 'M' + [char]0x00FC + 'ller'
                Mock Invoke-WebRequest { & $script:Respond ('{"_embedded":{"users":[{"id":"a","name":"' + $name + '"}]}}') }

                $users = @(Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection)
                [string]::Equals($users[0].name, $name, [StringComparison]::Ordinal) | Should-BeTrue
            }
        }
    }

    Context 'Pagination' {

        It 'follows next links and returns the items from every page' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest -ParameterFilter { $Uri -notlike '*page2*' } {
                    & $script:Respond '{"_embedded":{"users":[{"id":"a"},{"id":"b"}]},"_links":{"next":{"href":"https://api.pingone.com/v1/page2"}}}'
                }
                Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*page2*' } {
                    & $script:Respond '{"_embedded":{"users":[{"id":"c"}]}}'
                }

                @(Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection).id |
                    Should-BeCollection @('a', 'b', 'c')
            }
        }

        It 'stops when a next link points back at the page just fetched' {
            # Without the guard a self-referencing link fetches forever.
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    & $script:Respond ('{"_embedded":{"users":[{"id":"a"}]},"_links":{"next":{"href":"' + $Uri + '"}}}')
                }

                @(Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection) |
                    Should-BeCollection -Count 1
                Should-Invoke Invoke-WebRequest -Times 1 -Exactly
            }
        }

        It 'emits items one by one, so a pipeline filter selects a single item' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest {
                    & $script:Respond '{"_embedded":{"resources":[{"id":"1","name":"Orders API"},{"id":"2","name":"Reports API"}]}}'
                }

                $match = @(Invoke-PingOneRequest -Method GET -Path 'resources' -Paginate -Connection $script:Connection |
                        Where-Object name -eq 'Orders API')
                $match | Should-BeCollection -Count 1
                $match[0].id | Should-Be '1'
            }
        }

        It 'returns nothing, not a wrapped empty array, for an empty collection' {
            # A wrapped empty array is a one-element array, and "if (@(...))" on it has bitten
            # callers checking whether something already exists.
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '{"_embedded":{"users":[]}}' }
                @(Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $script:Connection) |
                    Should-BeCollection -Count 0
            }
        }

        It 'returns nothing for an empty response body, such as a DELETE' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { & $script:Respond '' }
                Invoke-PingOneRequest -Method DELETE -Path 'groups/x' -Connection $script:Connection | Should-BeNull
            }
        }
    }

    Context 'Errors' {

        It 'returns nothing for an error code the caller asked to ignore' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { throw 'boom' }
                Mock Get-PingOneErrorDetail { [PSCustomObject]@{ Status = 404; Code = 'NOT_FOUND'; Summary = 'NOT_FOUND: gone' } }
                Invoke-PingOneRequest -Method DELETE -Path 'groups/x' -IgnoreError 'NOT_FOUND' -Connection $script:Connection |
                    Should-BeNull
            }
        }

        It 'throws with the code and the summary for anything else' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { throw 'boom' }
                Mock Get-PingOneErrorDetail { [PSCustomObject]@{ Status = 400; Code = 'INVALID_DATA'; Summary = 'INVALID_DATA on name: taken' } }
                { Invoke-PingOneRequest -Method POST -Path 'groups' -Body @{ name = 'x' } -Connection $script:Connection } |
                    Should-Throw -ExceptionMessage '*INVALID_DATA on name*'
            }
        }

        It 'restores the progress preference even when the call throws' {
            InModuleScope TestEnvironment {
                Mock Invoke-WebRequest { throw 'boom' }
                Mock Get-PingOneErrorDetail { [PSCustomObject]@{ Status = 500; Code = 'UNEXPECTED_ERROR'; Summary = 'x' } }
                $ProgressPreference = 'Continue'
                try { $null = Invoke-PingOneRequest -Method GET -Path 'users' -Connection $script:Connection } catch { $null = $_ }
                $ProgressPreference | Should-Be 'Continue'
            }
        }
    }
}
