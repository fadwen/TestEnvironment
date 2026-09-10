#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    After an interactive sign-in the module tells the person whether to bootstrap, and with
    which command. That decision rests on two facts from two places - a tagged application in
    the tenant, and a credential record on this machine - and every combination of them is a
    different instruction. Each combination is pinned here, including the one where the
    delegated token cannot list applications at all, because sending someone to
    New-TestServiceApp when the app exists, or to Connect-TestEnvironment with a record whose
    application is gone, both cost a confused ten minutes at exactly the wrong moment.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-EntraBootstrapState' -Tag 'Unit' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:EntraConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                TenantName     = 'Contoso'
                ClientId       = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
                AuthMode       = 'DeviceCode'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ZZ-TEST-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            # The record lives under TestDrive so each test decides whether one exists.
            $script:RecordPath = Join-Path $TestDrive 'tenant.serviceapp.json'
            Remove-Item -LiteralPath $script:RecordPath -Force -ErrorAction SilentlyContinue
            Mock Get-TestCredentialPath { $script:RecordPath }

            # What the tenant holds. The service app is recognised by its tag, not its name,
            # and an untagged app with the prefix is a seeded object, not a bootstrap.
            $script:TenantApps = @()
            Mock Invoke-EntraRequest {
                if ($Method -eq 'GET' -and $Path -eq '/applications') { return $script:TenantApps }
                throw "Unexpected request $Method $Path"
            }
        }
    }

    It 'says ReadyToConnect when the record names an app that is in the tenant' {
        InModuleScope TestEnvironment {
            $script:TenantApps = @([PSCustomObject]@{ id = 'obj'; appId = 'client-1'; displayName = 'ZZ-TEST-ServiceApp'; tags = @('ZZ-TEST-seed', 'EntraEnvironmentServiceApp') })
            @{ clientId = 'client-1'; keyProtection = 'SecretStore'; vaultName = 'EntraEnvironment'; certificateThumbprint = 'ABC' } |
                ConvertTo-Json | Set-Content -LiteralPath $script:RecordPath

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'ReadyToConnect'
            $state.RecordMatchesApp | Should-BeTrue
            $state.Commands[0] | Should-Be 'Connect-TestEnvironment -Provider Entra -TenantId 00000000-0000-0000-0000-000000000001 -UseSecretStore'
            $state.Commands | Should-ContainCollection @('Get-TestServiceApp -TestCredential')
        }
    }

    It 'names the client id and thumbprint when the key is in the certificate store' {
        InModuleScope TestEnvironment {
            $script:TenantApps = @([PSCustomObject]@{ id = 'obj'; appId = 'client-1'; displayName = 'ZZ-TEST-ServiceApp'; tags = @('EntraEnvironmentServiceApp') })
            @{ clientId = 'client-1'; certificateThumbprint = 'ABC123' } |
                ConvertTo-Json | Set-Content -LiteralPath $script:RecordPath

            $state = Get-EntraBootstrapState

            $state.KeyProtection | Should-Be 'CertificateStore'
            $state.Commands[0] | Should-Be 'Connect-TestEnvironment -Provider Entra -TenantId 00000000-0000-0000-0000-000000000001 -ClientId client-1 -CertificateThumbprint ABC123'
        }
    }

    It 'says AppWithoutCredential when the app exists and this machine has no record' {
        InModuleScope TestEnvironment {
            $script:TenantApps = @([PSCustomObject]@{ id = 'obj'; appId = 'client-1'; displayName = 'ZZ-TEST-ServiceApp'; tags = @('EntraEnvironmentServiceApp') })

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'AppWithoutCredential'
            $state.RecordExists | Should-BeFalse
            $state.Commands | Should-BeCollection @('New-TestServiceApp -Force')
        }
    }

    It 'says AppWithoutCredential when the record names a different app than the tenant holds' {
        # A record copied from another machine, or left from a bootstrap that was since
        # replaced elsewhere. Connecting with it fails at token time; -Force is the answer.
        InModuleScope TestEnvironment {
            $script:TenantApps = @([PSCustomObject]@{ id = 'obj'; appId = 'client-2'; displayName = 'ZZ-TEST-ServiceApp'; tags = @('EntraEnvironmentServiceApp') })
            @{ clientId = 'client-1'; keyProtection = 'SecretStore' } | ConvertTo-Json | Set-Content -LiteralPath $script:RecordPath

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'AppWithoutCredential'
            $state.RecordMatchesApp | Should-BeFalse
            $state.Commands | Should-BeCollection @('New-TestServiceApp -Force')
        }
    }

    It 'says StaleRecord when the record names an app the tenant no longer has' {
        InModuleScope TestEnvironment {
            @{ clientId = 'client-1'; keyProtection = 'SecretStore' } | ConvertTo-Json | Set-Content -LiteralPath $script:RecordPath

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'StaleRecord'
            $state.Commands | Should-BeCollection @('New-TestServiceApp')
        }
    }

    It 'says NothingYet on a tenant that has never been bootstrapped from anywhere' {
        InModuleScope TestEnvironment {
            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'NothingYet'
            $state.Commands[0] | Should-Be 'New-TestServiceApp'
        }
    }

    It 'does not mistake a seeded application for the service app' {
        # Same prefix, no tag. It is one of the applications New-EntraApplication creates, and
        # treating it as the bootstrap would send the person to connect as something that has
        # no credential at all.
        InModuleScope TestEnvironment {
            $script:TenantApps = @([PSCustomObject]@{ id = 'obj'; appId = 'seeded'; displayName = 'ZZ-TEST-Expense Portal'; tags = @('ZZ-TEST-seed') })

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'NothingYet'
            $state.Applications.Count | Should-Be 0
        }
    }

    It 'says Unknown, with both options, when the sign-in cannot list applications' {
        # A delegated token without Application.Read.All. Not knowing is reported as such
        # rather than as "nothing yet", which would send the person to create a duplicate.
        InModuleScope TestEnvironment {
            Mock Invoke-EntraRequest { throw 'Graph GET v1.0/applications failed with HTTP 403: accessDenied' }
            @{ clientId = 'client-1'; keyProtection = 'SecretStore' } | ConvertTo-Json | Set-Content -LiteralPath $script:RecordPath

            $state = Get-EntraBootstrapState

            $state.Scenario | Should-Be 'Unknown'
            $state.TenantChecked | Should-BeFalse
            $state.CheckError | Should-MatchString '403'
            $state.Commands[0] | Should-MatchString '^Connect-TestEnvironment -Provider Entra'
            $state.Commands[1] | Should-Be 'New-TestServiceApp -Force'
        }
    }

    It 'never breaks the connect that just succeeded' {
        # Whatever goes wrong in the lookup, the connection was already proven against
        # /organization and must stay usable. The banner is advice, not a gate.
        InModuleScope TestEnvironment {
            Mock Get-EntraBootstrapState { throw 'unexpected' }
            Mock Write-Host { }
            Mock New-EntraDeviceCodeToken { @{ AccessToken = 't'; RefreshToken = 'r'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } }
            Mock Get-EntraTokenRole { @() }
            Mock Invoke-EntraRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                            id = '00000000-0000-0000-0000-000000000001'; displayName = 'Contoso'
                            verifiedDomains = @([PSCustomObject]@{ name = 'contoso.onmicrosoft.com'; isInitial = $true })
                        }) }
            }

            $result = Connect-EntraEnvironment -TenantId '00000000-0000-0000-0000-000000000001' -Interactive -PassThru

            $result.TenantName | Should-Be 'Contoso'
            $script:EntraConnection.AuthMode | Should-Be 'DeviceCode'
        }
    }
}

Describe 'Write-EntraBootstrapNextStep' -Tag 'Unit' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:HostLines = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host { $script:HostLines.Add([string]$Object) }
        }
    }

    It 'prints every command the state carries, using the exported dispatcher names' {
        InModuleScope TestEnvironment {
            $state = [PSCustomObject]@{
                PSTypeName = 'EntraBootstrapState'; Scenario = 'ReadyToConnect'; TenantName = 'Contoso'
                Applications = @([PSCustomObject]@{ DisplayName = 'ZZ-TEST-ServiceApp'; ClientId = 'client-1' })
                RecordClientId = 'client-1'; RecordExists = $true; KeyProtection = 'SecretStore'; CheckError = $null
                Commands = @('Connect-TestEnvironment -Provider Entra -TenantId t -UseSecretStore', 'Get-TestServiceApp -TestCredential')
            }

            Write-EntraBootstrapNextStep -State $state

            $joined = $script:HostLines -join "`n"
            $joined | Should-MatchString 'ZZ-TEST-ServiceApp'
            $joined | Should-MatchString 'Connect-TestEnvironment -Provider Entra -TenantId t -UseSecretStore'
            $joined | Should-MatchString 'Get-TestServiceApp -TestCredential'
            $joined | Should-NotMatchString 'Connect-EntraEnvironment'
        }
    }

    It 'explains the reason when the tenant could not be read' {
        InModuleScope TestEnvironment {
            $state = [PSCustomObject]@{
                PSTypeName = 'EntraBootstrapState'; Scenario = 'Unknown'; TenantName = 'Contoso'
                Applications = @(); RecordClientId = $null; RecordExists = $false; KeyProtection = $null
                CheckError = 'HTTP 403: accessDenied'
                Commands = @('New-TestServiceApp', 'New-TestServiceApp -Force')
            }

            Write-EntraBootstrapNextStep -State $state

            ($script:HostLines -join "`n") | Should-MatchString 'HTTP 403'
        }
    }
}
