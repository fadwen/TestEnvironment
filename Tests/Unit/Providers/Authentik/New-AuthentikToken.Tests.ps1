#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A token is a credential, and two things about the seed's handling of them are pinned: the
    secret is never read back or returned, and the three expiry states the CSV describes -
    never, in twenty minutes, a day ago - reach the API as the expiring flag and an absolute
    time rather than as a minute count. Minutes, because an instance caps an app password at
    its default token duration and refuses a month. The identifier carries the slug prefix, which with the seeded
    owner is what teardown proves ownership by.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikToken' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Users') {
                    return @(
                        [PSCustomObject]@{ pk = 1; username = 'awhitfield' }
                        [PSCustomObject]@{ pk = 6; username = 'talvarez' }
                        [PSCustomObject]@{ pk = 10; username = 'svc-reporting' }
                    )
                }
                @()
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/core/tokens/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ identifier = $Body.identifier; key = 'SECRET-THAT-MUST-NOT-LEAK' }
                }
                return [PSCustomObject]@{ identifier = $Body.identifier }
            }
        }
    }

    It 'creates every token on its seeded user with the slug prefix on the identifier' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikToken -PassThru -Confirm:$false

            $r.TotalTokens | Should-Be 3
            $r.CreatedTokens | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            # The identifier has to be a string, not a one-element array: the loop variable once
            # shared its name with the [string[]] parameter and the JSON carried an array.
            @($script:Created | Where-Object { $_.identifier -isnot [string] }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { -not $_.identifier.StartsWith('zz-test-') }) | Should-BeCollection -Count 0
            ($script:Created | Where-Object { $_.identifier -eq 'zz-test-reporting-service' }).user | Should-Be 10
        }
    }

    It 'sends the three expiry states as the API expects them' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikToken -PassThru -Confirm:$false

            $never = $script:Created | Where-Object { $_.identifier -eq 'zz-test-reporting-service' }
            $never.expiring | Should-BeFalse
            $never.ContainsKey('expires') | Should-BeFalse

            $soon = $script:Created | Where-Object { $_.identifier -eq 'zz-test-ada-cli' }
            $soon.expiring | Should-BeTrue
            ([DateTimeOffset]::Parse($soon.expires)) | Should-BeGreaterThan ([DateTimeOffset]::UtcNow.AddMinutes(15))
            ([DateTimeOffset]::Parse($soon.expires)) | Should-BeLessThan ([DateTimeOffset]::UtcNow.AddMinutes(30))

            $stale = $script:Created | Where-Object { $_.identifier -eq 'zz-test-tomas-stale' }
            ([DateTimeOffset]::Parse($stale.expires)) | Should-BeLessThan ([DateTimeOffset]::UtcNow)
            # An API token's expiry is server-assigned, so only an app password can be seeded expired.
            $stale.intent | Should-Be 'app_password'
            ($r.Tokens | Where-Object Key -eq 'tomas-stale').Expired | Should-BeTrue
            ($r.Tokens | Where-Object Key -eq 'ada-cli').Expired | Should-BeFalse
        }
    }

    It 'never returns or requests the secret' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikToken -PassThru -Confirm:$false

            ($r | ConvertTo-Json -Depth 5) | Should-NotMatchString 'SECRET-THAT-MUST-NOT-LEAK'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -like '*view_key*' }
        }
    }

    It 'skips a token whose user does not exist and reports it' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikToken -Identifier ada-cli -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedTokens | Should-Be 0
            @($r.Errors).Count | Should-Be 1
        }
    }

    It 'updates a token that already exists by its identifier' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Users') { return @([PSCustomObject]@{ pk = 1; username = 'awhitfield' }) }
                if ($Type -eq 'Tokens') { return @([PSCustomObject]@{ identifier = 'zz-test-ada-cli' }) }
                @()
            }

            $r = New-AuthentikToken -Identifier ada-cli -PassThru -Confirm:$false

            $r.UpdatedTokens | Should-Be 1
            # A PATCH that omits the owner reassigns the token to the caller, verified live, so
            # the update always carries it.
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/core/tokens/zz-test-ada-cli/' -and $Body.user -eq 1 }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikToken -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
