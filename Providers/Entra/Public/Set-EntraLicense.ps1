function Set-EntraLicense {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Assigns licences by group and directly, so the assignment path is ambiguous on purpose
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraLicenseAssignment')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SkuPartNumber,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $cache = @{}

    $skus = @((Invoke-EntraRequest -Method GET -Path '/subscribedSkus').value)
    if (-not $skus) {
        Write-Error "The tenant reports no subscribed SKUs, so nothing can be licensed." -ErrorAction Stop
        return
    }

    $available = @($skus | Where-Object { ($_.prepaidUnits.enabled - $_.consumedUnits) -gt 0 })

    if ($SkuPartNumber) {
        $sku = $skus | Where-Object { $_.skuPartNumber -eq $SkuPartNumber } | Select-Object -First 1
        if (-not $sku) {
            Write-Error ("The tenant has no SKU called '$SkuPartNumber'. Available: " +
                (($skus.skuPartNumber | Sort-Object) -join ', ')) -ErrorAction Stop
            return
        }
        $free = $sku.prepaidUnits.enabled - $sku.consumedUnits
        if ($free -le 0) {
            Write-Error ("SKU '$SkuPartNumber' has no free units ($($sku.consumedUnits) of " +
                "$($sku.prepaidUnits.enabled) consumed). Assigning from it would fail.") -ErrorAction Stop
            return
        }
    }
    else {
        if (-not $available) {
            Write-Warning ("No subscribed SKU has a free unit, so no licence can be assigned. The licensing " +
                "shapes will be absent from this environment; everything else still seeds.")
            return
        }
        # Prefer the free SKUs. They are the ones a tenant is most likely to have thousands
        # spare of, and consuming a paid seat for a lab account is a real cost.
        $preferred = 'FLOW_FREE', 'POWER_BI_STANDARD', 'TEAMS_EXPLORATORY', 'RMSBASIC'
        $sku = $available | Sort-Object @{ Expression = {
                $rank = $preferred.IndexOf($_.skuPartNumber)
                if ($rank -lt 0) { [int]::MaxValue } else { $rank }
            }
        } | Select-Object -First 1
    }

    Write-Verbose "Licensing with $($sku.skuPartNumber) ($($sku.skuId))"
    $results = [System.Collections.Generic.List[object]]::new()

    # Group-based first. Every member inherits it, which is the path the direct assignment
    # below then duplicates for one of them.
    $groupId = Resolve-EntraSeededId -Key 'lic-powerbi' -Kind Group -Cache $cache -Connection $connection
    if (-not $groupId) {
        Write-Warning "The seeded licence group does not exist, so no group-based assignment was made."
    }
    elseif ($PSCmdlet.ShouldProcess("Group lic-powerbi", "Assign $($sku.skuPartNumber)")) {
        Write-TestProgress -Activity 'Assigning licences' -Status 'group-based' -PercentComplete 33 -ShowProgress:$ShowProgress
        try {
            Invoke-EntraRequest -Method POST -Path "/groups/$groupId/assignLicense" -RetryOnNotFound -Body @{
                addLicenses    = @(@{ skuId = $sku.skuId; disabledPlans = @() })
                removeLicenses = @()
            } | Out-Null

            $results.Add([PSCustomObject]@{
                    PSTypeName    = 'EntraLicenseAssignment'
                    Target        = 'lic-powerbi'
                    TargetType    = 'Group'
                    SkuPartNumber = $sku.skuPartNumber
                    Path          = 'Group-based'
                    Succeeded     = $true
                    Detail        = 'Members inherit this licence'
                })
            Write-Verbose "Assigned $($sku.skuPartNumber) to the seeded licence group"
        }
        catch {
            Write-Warning "Group licence assignment failed: $($_.Exception.Message)"
        }
    }

    # Direct assignments. Priya duplicates what she already inherits; Owen fails because he
    # has no usageLocation, which is the point of him.
    $directTargets = @(
        [PSCustomObject]@{ Key = 'praghunathan'; Note = 'Also inherits this SKU from the group, so her assignment path is ambiguous' }
        [PSCustomObject]@{ Key = 'ofitzgerald'; Note = 'Has no usageLocation, so Entra refuses the assignment' }
    )

    $index = 0
    foreach ($target in $directTargets) {
        $index++
        Write-TestProgress -Activity 'Assigning licences' -Status $target.Key `
            -PercentComplete (33 + [int](67 * $index / $directTargets.Count)) -ShowProgress:$ShowProgress

        $userId = Resolve-EntraSeededId -Key $target.Key -Kind User -Cache $cache -Connection $connection
        if (-not $userId) {
            Write-Warning "Seeded user '$($target.Key)' does not exist; skipping its direct licence."
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($target.Key, "Assign $($sku.skuPartNumber) directly")) { continue }

        try {
            Invoke-EntraRequest -Method POST -Path "/users/$userId/assignLicense" -RetryOnNotFound -Body @{
                addLicenses    = @(@{ skuId = $sku.skuId; disabledPlans = @() })
                removeLicenses = @()
            } | Out-Null

            $results.Add([PSCustomObject]@{
                    PSTypeName    = 'EntraLicenseAssignment'
                    Target        = $target.Key
                    TargetType    = 'User'
                    SkuPartNumber = $sku.skuPartNumber
                    Path          = 'Direct'
                    Succeeded     = $true
                    Detail        = $target.Note
                })
            Write-Verbose "Assigned $($sku.skuPartNumber) directly to '$($target.Key)'"
        }
        catch {
            # Owen is expected to land here. Reported rather than thrown, because a seeding
            # step that stops the run over a failure it was designed to produce is worse than
            # useless.
            Write-Warning "Direct licence assignment to '$($target.Key)' failed: $($_.Exception.Message)"
            $results.Add([PSCustomObject]@{
                    PSTypeName    = 'EntraLicenseAssignment'
                    Target        = $target.Key
                    TargetType    = 'User'
                    SkuPartNumber = $sku.skuPartNumber
                    Path          = 'Direct'
                    Succeeded     = $false
                    Detail        = $_.Exception.Message
                })
        }
    }

    Write-TestProgress -Activity 'Assigning licences' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $results.ToArray() }
}
