#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The bootstrap creates a privileged application, so these tests are mostly about what it
    does not do and what it refuses to claim.

    The two that matter most:

    - The private key is never sent. Only the DER-encoded public certificate goes to Entra, and
      the assertion below decodes what was actually uploaded to prove there is no key in it.
    - Success is not reported until the new application has authenticated. An application that
      exists, is consented, and cannot get a token is the worst outcome of the three, because
      the failure surfaces later and somewhere else.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-EntraServiceApp' -Tag 'Unit', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:EntraConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                TenantName     = 'Contoso'
                ClientId       = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
                AuthMode       = 'DeviceCode'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            $script:Calls = [System.Collections.Generic.List[object]]::new()
            $script:Consented = [System.Collections.Generic.List[string]]::new()

            Mock Start-Sleep { }
            Mock Get-TestCredentialPath { Join-Path ([System.IO.Path]::GetTempPath()) 'entralab-test.serviceapp.json' }
            Mock Set-Content { }
            Mock Get-EntraAccessToken { $null }

            # The suite must not touch the machine's certificate store. This mock is why
            # Save-TestCertificate exists as a function at all: the inline X509Store
            # calls it replaced could not be intercepted, and running these tests installed a
            # certificate into the developer's personal store every single time.
            Mock Save-TestCertificate { $true }

            Mock Invoke-EntraRequest {
                $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })

                if ($Method -eq 'GET' -and $Path -eq '/applications') { return @() }
                if ($Path -like "*servicePrincipals?`$filter=appId eq '00000003*") {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'graph-sp-id' }) }
                }
                if ($Method -eq 'GET' -and $Path -eq '/servicePrincipals') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/applications') {
                    return [PSCustomObject]@{ id = 'app-object-id'; appId = 'app-client-id' }
                }
                if ($Method -eq 'POST' -and $Path -eq '/servicePrincipals') {
                    return [PSCustomObject]@{ id = 'new-sp-id' }
                }
                if ($Path -like '*/appRoleAssignments') {
                    $script:Consented.Add($Body.appRoleId)
                    return [PSCustomObject]@{ id = 'assignment' }
                }
                return $null
            }
        }
    }

    Context 'The private key never leaves the machine' {

        It 'uploads a certificate that contains no private key' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -Confirm:$false 6>$null | Out-Null

                $patch = $script:Calls | Where-Object { $_.Method -eq 'PATCH' -and $_.Path -like '/applications/*' } | Select-Object -First 1
                $patch | Should-NotBeNull

                $uploaded = @($patch.Body.keyCredentials)[0]
                $uploaded.type | Should-Be 'AsymmetricX509Cert'
                $uploaded.usage | Should-Be 'Verify'

                # Decoded back into a certificate, this must be the public half only. If a PFX
                # or a key had been sent, HasPrivateKey would be true.
                $bytes = [Convert]::FromBase64String($uploaded.key)
                $sent = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
                try {
                    $sent.HasPrivateKey | Should-BeFalse
                    $sent.Subject | Should-MatchString 'ENTRALAB-ServiceApp'
                }
                finally { $sent.Dispose() }
            }
        }

        It 'never sends anything resembling a private key blob' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -Confirm:$false 6>$null | Out-Null

                foreach ($call in $script:Calls) {
                    if ($null -eq $call.Body) { continue }
                    $json = $call.Body | ConvertTo-Json -Depth 10 -Compress
                    $json | Should-NotMatchString 'PRIVATE KEY'
                    $json | Should-NotMatchString 'passwordCredentials'
                }
            }
        }
    }

    Context 'Consent' {

        It 'grants consent as appRoleAssignments on the Graph service principal' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -Confirm:$false 6>$null | Out-Null

                $assignments = @($script:Calls | Where-Object { $_.Path -like '*/appRoleAssignments' })
                $assignments.Count | Should-BeGreaterThan 0
                # resourceId is Graph, principalId is the new app: consent is the app being
                # assigned a role ON Graph, not the other way round.
                $assignments[0].Body.resourceId | Should-Be 'graph-sp-id'
                $assignments[0].Body.principalId | Should-Be 'new-sp-id'
            }
        }

        It 'grants only the permissions asked for' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -Confirm:$false -Scope User.ReadWrite.All, Group.ReadWrite.All 6>$null | Out-Null

                $script:Consented.Count | Should-Be 2
                @($script:Consented) | Should-ContainCollection @('741f803b-c850-494e-b5df-cde7c675a1ca') -IgnoreOrder
            }
        }

        It 'refuses a permission it does not have a role id for' {
            InModuleScope TestEnvironment {
                # Guesswork here would mean sending a GUID Entra rejects, or worse, one that
                # grants something else.
                { New-EntraServiceApp -Confirm:$false -Scope 'Directory.ReadWrite.All' -ErrorAction Stop } |
                    Should-Throw -ExceptionMessage '*Unknown permission*'
            }
        }

        It 'grants the full catalogue by default' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -Confirm:$false 6>$null | Out-Null

                $catalogue = @(Get-EntraSeedData -Name 'EntraServiceAppPermissions')
                $script:Consented.Count | Should-Be $catalogue.Count
            }
        }
    }

    Context 'Restraint' {

        It 'creates nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                New-EntraServiceApp -WhatIf 6>$null | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count | Should-Be 0
            }
        }

        It 'refuses to replace an existing app without -Force' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                    if ($Method -eq 'GET' -and $Path -eq '/applications') {
                        return @([PSCustomObject]@{ id = 'existing'; appId = 'existing-client'; displayName = 'ENTRALAB-ServiceApp' })
                    }
                    return $null
                }

                New-EntraServiceApp -Confirm:$false -WarningAction SilentlyContinue 6>$null | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count | Should-Be 0
            }
        }

        It 'tags the app so teardown will not sweep it up' {
            InModuleScope TestEnvironment {
                # The single most important property of the bootstrapped app: without this tag
                # Remove-EntraEnvironment would delete the credential it is using.
                New-EntraServiceApp -Confirm:$false 6>$null | Out-Null

                $create = $script:Calls | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/applications' } | Select-Object -First 1
                @($create.Body.tags) | Should-ContainCollection @('EntraEnvironmentServiceApp')
            }
        }
    }

    Context 'Honesty about the handover' {

        It 'reports HandoverVerified false when the new app cannot yet authenticate' {
            InModuleScope TestEnvironment {
                Mock Get-EntraAccessToken { throw 'not published yet' }

                $result = New-EntraServiceApp -Confirm:$false -PassThru -WarningAction SilentlyContinue 6>$null

                $result.HandoverVerified | Should-BeFalse
            }
        }

        It 'reports which permissions were refused rather than claiming them all' {
            InModuleScope TestEnvironment {
                Mock Invoke-EntraRequest {
                    $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                    if ($Method -eq 'GET' -and $Path -eq '/applications') { return @() }
                    if ($Path -like "*servicePrincipals?`$filter=appId eq '00000003*") {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'graph-sp-id' }) }
                    }
                    if ($Method -eq 'GET' -and $Path -eq '/servicePrincipals') { return @() }
                    if ($Method -eq 'POST' -and $Path -eq '/applications') { return [PSCustomObject]@{ id = 'a'; appId = 'b' } }
                    if ($Method -eq 'POST' -and $Path -eq '/servicePrincipals') { return [PSCustomObject]@{ id = 'sp' } }
                    if ($Path -like '*/appRoleAssignments') { throw 'Authorization_RequestDenied' }
                    return $null
                }

                $result = New-EntraServiceApp -Confirm:$false -PassThru -WarningAction SilentlyContinue 6>$null

                $result.GrantedPermissions.Count | Should-Be 0
                $result.RefusedPermissions.Count | Should-BeGreaterThan 0
            }
        }
    }
}

Describe 'Service app exclusion from teardown' -Tag 'Unit', 'Safety' {

    It 'never returns the bootstrapped app from ordinary application discovery' {
        InModuleScope TestEnvironment {
            # The regression this guards is catastrophic rather than merely wrong: teardown
            # would delete its own credential partway through and strand the rest.
            $connection = @{
                TenantId = 't'; ClientId = 'c'; GraphBaseUri = 'https://graph.microsoft.com'
                Prefix = 'ENTRALAB-'; UpnSuffix = 'contoso.onmicrosoft.com'
                AccessToken = 'x'; TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); TokenRoles = @()
            }

            Mock Invoke-EntraRequest {
                if ($Path -eq '/directory/administrativeUnits') { return @() }
                if ($Path -eq '/applications') {
                    return @(
                        [PSCustomObject]@{ id = 'seeded'; appId = 'a1'; displayName = 'ENTRALAB-Expense Portal'; tags = @('ENTRALAB-seed') }
                        [PSCustomObject]@{ id = 'bootstrap'; appId = 'a2'; displayName = 'ENTRALAB-ServiceApp'; tags = @('ENTRALAB-seed', 'EntraEnvironmentServiceApp') }
                    )
                }
                return @()
            }

            $found = @(Get-EntraSeededObject -Type Applications -Connection $connection)

            $found.Count | Should-Be 1
            $found[0].id | Should-Be 'seeded'
        }
    }

    It 'never returns the bootstrapped service principal either' {
        InModuleScope TestEnvironment {
            $connection = @{
                TenantId = 't'; ClientId = 'c'; GraphBaseUri = 'https://graph.microsoft.com'
                Prefix = 'ENTRALAB-'; UpnSuffix = 'contoso.onmicrosoft.com'
                AccessToken = 'x'; TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); TokenRoles = @()
            }

            Mock Invoke-EntraRequest {
                if ($Path -eq '/directory/administrativeUnits') { return @() }
                if ($Path -eq '/servicePrincipals') {
                    return @(
                        [PSCustomObject]@{ id = 'seeded-sp'; appId = 'a1'; displayName = 'ENTRALAB-Expense Portal'; tags = @('ENTRALAB-seed') }
                        [PSCustomObject]@{ id = 'bootstrap-sp'; appId = 'a2'; displayName = 'ENTRALAB-ServiceApp'; tags = @('ENTRALAB-seed', 'EntraEnvironmentServiceApp') }
                    )
                }
                return @()
            }

            $found = @(Get-EntraSeededObject -Type ServicePrincipals -Connection $connection)

            $found.Count | Should-Be 1
            $found[0].id | Should-Be 'seeded-sp'
        }
    }
}
