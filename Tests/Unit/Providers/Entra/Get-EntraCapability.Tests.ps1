#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The licence probe the Entra connect runs once. The seed skips a step on its word, so the word
    has to be right in both directions: a plan counts only when its SKU is enabled and the plan is
    provisioned, P2 or Governance implies P1, and a tenant whose SKUs the app cannot read answers
    "unknown" - which the seed reads as "attempt everything" - rather than "unlicensed". The probe
    may remove noise; it may never remove a step the tenant would have run.

    Everything is mocked. The tenant is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-EntraCapability' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Connection = @{ TenantId = 'tenant-1'; GraphBaseUri = 'https://graph.microsoft.com'; AccessToken = 't' }
            $script:Skus = @()
            Mock Invoke-EntraRequest { [PSCustomObject]@{ value = $script:Skus } }
        }
    }

    It 'reads a free tenant as neither P1 nor P2, and known' {
        InModuleScope TestEnvironment {
            $script:Skus = @([PSCustomObject]@{ skuPartNumber = 'O365_BUSINESS'; capabilityStatus = 'Enabled'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'EXCHANGE_S_STANDARD'; provisioningStatus = 'Success' }) })
            $capability = Get-EntraCapability -Connection $script:Connection
            $capability.Known | Should-BeTrue
            $capability.EntraP1 | Should-BeFalse
            $capability.EntraP2 | Should-BeFalse
            @($capability.Plans) | Should-BeCollection @('EXCHANGE_S_STANDARD')
            Should-Invoke Invoke-EntraRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/subscribedSkus' }
        }
    }

    It 'reads P1 from a provisioned AAD_PREMIUM plan, and P2 or Governance as both' {
        InModuleScope TestEnvironment {
            $script:Skus = @([PSCustomObject]@{ skuPartNumber = 'EMS'; capabilityStatus = 'Enabled'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Success' }) })
            $p1 = Get-EntraCapability -Connection $script:Connection
            $p1.EntraP1 | Should-BeTrue
            $p1.EntraP2 | Should-BeFalse

            $script:Skus = @([PSCustomObject]@{ skuPartNumber = 'AAD_PREMIUM_P2'; capabilityStatus = 'Enabled'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) })
            $p2 = Get-EntraCapability -Connection $script:Connection
            $p2.EntraP1 | Should-BeTrue
            $p2.EntraP2 | Should-BeTrue

            $script:Skus = @([PSCustomObject]@{ skuPartNumber = 'Microsoft_Entra_ID_Governance'; capabilityStatus = 'Enabled'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'Entra_Identity_Governance'; provisioningStatus = 'Success' }) })
            (Get-EntraCapability -Connection $script:Connection).EntraP2 | Should-BeTrue
        }
    }

    It 'ignores a plan on a suspended SKU and a plan that is not provisioned' {
        InModuleScope TestEnvironment {
            $script:Skus = @(
                [PSCustomObject]@{ skuPartNumber = 'AAD_PREMIUM_P2'; capabilityStatus = 'Suspended'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }) }
                [PSCustomObject]@{ skuPartNumber = 'EMS'; capabilityStatus = 'Enabled'; servicePlans = @([PSCustomObject]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Disabled' }) }
            )
            $capability = Get-EntraCapability -Connection $script:Connection
            $capability.Known | Should-BeTrue
            $capability.EntraP1 | Should-BeFalse
            $capability.EntraP2 | Should-BeFalse
        }
    }

    It 'answers unknown, not unlicensed, when the SKUs cannot be read' {
        InModuleScope TestEnvironment {
            Mock Invoke-EntraRequest { throw 'Graph GET /subscribedSkus failed with HTTP 403' }
            $capability = Get-EntraCapability -Connection $script:Connection
            $capability.Known | Should-BeFalse
            $capability.EntraP1 | Should-BeFalse
            $capability.EntraP2 | Should-BeFalse
        }
    }
}
