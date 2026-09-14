function Get-EntraCapability {
    <#
    .SYNOPSIS
        Reads once, at connect time, which licence-gated features the tenant can hold
    .DESCRIPTION
        Two of the seed's fourteen steps need a licence the tenant may not have: Conditional
        Access policies need Entra ID P1, and role eligibilities - Privileged Identity Management -
        need Entra ID P2 or Entra ID Governance. Without the probe each of those steps found out
        for itself, one refusal per object: nine policy failures and three eligibility warnings,
        each saying the same thing in Graph's words. With it, the connection knows before the
        first request, and the seed skips the step once with one message.

        The answer comes from the tenant's subscribed SKUs: a plan counts when its SKU is enabled
        and the plan itself is provisioned. A tenant that will not let the app read its SKUs -
        the read needs Organization.Read.All or Directory.Read.All, which the connect already
        requires for /organization - answers Known = $false, and every step is then attempted as
        before, so the probe can only ever remove noise, never a step the tenant would have run.
    .PARAMETER Connection
        The connection being established; the same hashtable Connect-EntraEnvironment builds
    .OUTPUTS
        PSCustomObject with Known, EntraP1, EntraP2 and Plans, the provisioned plan names
    .EXAMPLE
        PS> Get-EntraCapability -Connection $candidate

        Known True, EntraP1 False, EntraP2 False for a tenant on free Entra ID.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Connection
    )

    $plans = New-Object System.Collections.Generic.List[string]
    $known = $true
    try {
        foreach ($sku in @((Invoke-EntraRequest -Method GET -Path '/subscribedSkus' -Connection $Connection).value)) {
            if ([string]$sku.capabilityStatus -ne 'Enabled') { continue }
            foreach ($plan in @($sku.servicePlans)) {
                if ([string]$plan.provisioningStatus -eq 'Success' -and $plan.servicePlanName) { $plans.Add([string]$plan.servicePlanName) }
            }
        }
    }
    catch {
        $known = $false
        Write-Verbose "Could not read the tenant's subscribed SKUs, so its licences are unknown and every step will be attempted: $($_.Exception.Message)"
    }

    # P2 and Governance both carry Privileged Identity Management; either includes P1.
    $p2 = @($plans | Where-Object { $_ -match '^AAD_PREMIUM_P2$|GOVERNANCE' }).Count -gt 0
    $p1 = $p2 -or @($plans | Where-Object { $_ -eq 'AAD_PREMIUM' }).Count -gt 0

    return [PSCustomObject]@{
        PSTypeName = 'EntraCapability'
        Known      = $known
        EntraP1    = $p1
        EntraP2    = $p2
        Plans      = @($plans | Sort-Object -Unique)
    }
}
