#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The delegated scopes an interactive session asks for are derived from the service app's
    permission list rather than typed a second time, so the two cannot drift. Two names must
    differ, and both are the difference between an interactive session that can do the whole
    job and one that fails halfway: the device permission has no delegated form, and the
    OwnedBy grant that is right for the service app is wrong for a person who has to remove
    what the service app refuses. The device-code request has to carry the result correctly:
    Graph scopes prefixed with the resource, OpenID scopes bare, offline_access always.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:Csv = @(Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Entra\Data\EntraServiceAppPermissions.csv') -Encoding UTF8)
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-EntraDelegatedScope' -Tag 'Unit', 'Private' {

    It 'carries every permission in the CSV, in its delegated form' {
        $expected = @($script:Csv | ForEach-Object {
                switch ($_.Permission) {
                    'Device.ReadWrite.All' { 'Directory.AccessAsUser.All' }
                    'Application.ReadWrite.OwnedBy' { 'Application.ReadWrite.All' }
                    default { $_ }
                }
            } | Sort-Object -Unique)
        InModuleScope TestEnvironment -Parameters @{ expected = $expected } {
            param($expected)
            $scopes = @(Get-EntraDelegatedScope)
            @($scopes | Where-Object { $_ -notin 'openid', 'offline_access' }) | Should-BeCollection $expected
        }
    }

    It 'asks for the broad application scope, never the OwnedBy one' {
        InModuleScope TestEnvironment {
            $scopes = @(Get-EntraDelegatedScope)
            $scopes | Should-ContainCollection @('Application.ReadWrite.All')
            $scopes | Should-NotContainCollection @('Application.ReadWrite.OwnedBy')
        }
    }

    It 'asks for the delegated device scope in place of the application-only one' {
        InModuleScope TestEnvironment {
            $scopes = @(Get-EntraDelegatedScope)
            $scopes | Should-ContainCollection @('Directory.AccessAsUser.All')
            $scopes | Should-NotContainCollection @('Device.ReadWrite.All')
        }
    }

    It 'ends with the OpenID scopes the device-code flow needs' {
        InModuleScope TestEnvironment {
            $scopes = @(Get-EntraDelegatedScope)
            $scopes[-2..-1] | Should-BeCollection @('openid', 'offline_access')
        }
    }
}

Describe 'New-EntraDeviceCodeToken scope request' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Body = $null
            # The first request is the device-code request; capturing its body and then
            # throwing keeps the test from ever polling for a token.
            Mock Invoke-WebRequest {
                $script:Body = [System.Text.Encoding]::UTF8.GetString($Body)
                throw 'stop after the device-code request'
            }
            Mock Write-Host { }
        }
    }

    It 'prefixes Graph scopes with the resource, leaves OpenID scopes bare, and always adds offline_access' {
        InModuleScope TestEnvironment {
            try { $null = New-EntraDeviceCodeToken -TenantId t -Scope @('User.ReadWrite.All', 'openid') -ErrorAction SilentlyContinue } catch { $null = $_ }

            $pair = @(($script:Body -split '&') | Where-Object { $_ -like 'scope=*' })[0]
            $scope = [uri]::UnescapeDataString($pair.Substring(6))
            $scope | Should-Be 'https://graph.microsoft.com/User.ReadWrite.All openid offline_access'
        }
    }

    It 'sends .default as the resource default' {
        InModuleScope TestEnvironment {
            try { $null = New-EntraDeviceCodeToken -TenantId t -Scope '.default' -ErrorAction SilentlyContinue } catch { $null = $_ }

            $pair = @(($script:Body -split '&') | Where-Object { $_ -like 'scope=*' })[0]
            $scope = [uri]::UnescapeDataString($pair.Substring(6))
            $scope | Should-Be 'https://graph.microsoft.com/.default offline_access'
        }
    }

    It 'defaults to .default when no scope is given' {
        InModuleScope TestEnvironment {
            try { $null = New-EntraDeviceCodeToken -TenantId t -ErrorAction SilentlyContinue } catch { $null = $_ }

            $script:Body | Should-MatchString '\.default'
        }
    }
}

Describe 'Connect-EntraEnvironment -Interactive' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:AskedScope = $null
            Mock New-EntraDeviceCodeToken {
                $script:AskedScope = $Scope
                @{ AccessToken = 't'; RefreshToken = 'r'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) }
            }
            Mock Get-EntraTokenRole { @() }
            Mock Get-EntraBootstrapState { throw 'not under test' }
            Mock Invoke-EntraRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                            id = '00000000-0000-0000-0000-000000000001'; displayName = 'Contoso'
                            verifiedDomains = @([PSCustomObject]@{ name = 'contoso.onmicrosoft.com'; isInitial = $true })
                        }) }
            }
        }
    }

    It 'asks for the full delegated scope list by default' {
        InModuleScope TestEnvironment {
            Connect-EntraEnvironment -TenantId '00000000-0000-0000-0000-000000000001' -Interactive

            @($script:AskedScope) | Should-BeCollection @(Get-EntraDelegatedScope)
        }
    }

    It 'passes an explicit -Scope through unchanged' {
        InModuleScope TestEnvironment {
            Connect-EntraEnvironment -TenantId '00000000-0000-0000-0000-000000000001' -Interactive -Scope '.default'

            @($script:AskedScope) | Should-BeCollection @('.default')
        }
    }
}
