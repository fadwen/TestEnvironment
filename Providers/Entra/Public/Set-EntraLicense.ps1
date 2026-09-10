function Set-EntraLicense {
    <#
    .SYNOPSIS
        Assigns licences by group and directly, so the assignment path is ambiguous on purpose

    .DESCRIPTION
        Creates the one licensing shape that reporting scripts consistently get wrong: a user
        who holds the same licence twice, once inherited from a group and once assigned
        directly to the account.

        That user is Priya. She is a member of the seeded licence group, and the same SKU is
        also assigned to her account. Graph reports her assignedLicenses identically in both
        cases - the same skuId, once - and the only way to tell the paths apart is
        licenseAssignmentStates, where the inherited entry carries the group's object id in
        assignedByGroup and the direct entry carries null. A script that reads assignedLicenses
        and stops there cannot distinguish "remove this user from the group" from "remove the
        licence from this user", and will report the wrong remediation for one of them.

        Marcus is the second case worth having: he is disabled and still licensed, because
        disabling an account does not release its licence. That is a real and expensive
        oversight, and it is invisible unless a disabled account is actually holding one.

        Owen is the third, and he fails on purpose. He has no usageLocation, and Entra refuses
        to license a user without one. This is the most common licensing error there is and
        the message names the reason clearly, so the failure is reported and the run
        continues rather than treating it as fatal.

        The SKU is chosen at run time from what the tenant actually has spare rather than
        being hardcoded, because a seeding module that fails on a tenant with a different
        subscription mix is not much use. Anything with no free units is skipped, since
        assigning from an exhausted SKU fails for a reason that has nothing to do with this
        module.

    .PARAMETER SkuPartNumber
        Which SKU to assign. Defaults to the first one with free units, preferring the
        no-cost SKUs that a tenant is most likely to have spare.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns what was assigned

    .OUTPUTS
        EntraLicenseAssignment[] when -PassThru is supplied

    .EXAMPLE
        PS> Set-EntraLicense

        DESCRIPTION: Assigns an automatically chosen spare SKU by group and directly
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment

    .EXAMPLE
        PS> Set-EntraLicense -SkuPartNumber POWER_BI_STANDARD -PassThru

        DESCRIPTION: Uses a specific SKU
        OUTPUT: The group and user assignments made
        USE CASE: Reproducing a licence path against a SKU your own scripts care about

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
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
