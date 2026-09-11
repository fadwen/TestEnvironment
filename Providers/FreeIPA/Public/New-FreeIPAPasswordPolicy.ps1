function New-FreeIPAPasswordPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded password policies from Data\FreeIPAPasswordPolicies.csv, one per seeded group
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$GroupName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAPasswordPolicies.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($GroupName) {
        $rows = @($rows | Where-Object { $GroupName -contains $_.Group })
        $unknown = @($GroupName | Where-Object { $rows.Group -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalPolicies   = $rows.Count
        CreatedPolicies = 0
        UpdatedPolicies = 0
        Policies        = @()
        Errors          = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type PasswordPolicies -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    # The CSV columns, in the API's own attribute names.
    $attributeOf = [ordered]@{
        Priority     = 'cospriority'
        MaxLife      = 'krbmaxpwdlife'
        MinLife      = 'krbminpwdlife'
        History      = 'krbpwdhistorylength'
        MinClasses   = 'krbpwdmindiffchars'
        MinLength    = 'krbpwdminlength'
        MaxFail      = 'krbpwdmaxfailure'
        FailInterval = 'krbpwdfailurecountinterval'
        LockoutTime  = 'krbpwdlockoutduration'
        GraceLimit   = 'passwordgracelimit'
    }

    $policies = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $groupNameInRealm = Resolve-FreeIPASeedName -Key $row.Group -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess($groupNameInRealm, 'Create FreeIPA password policy')) { continue }
        try {
            $options = @{}
            foreach ($column in $attributeOf.Keys) {
                if ($row.$column -match '^-?\d+$') { $options[$attributeOf[$column]] = [int]$row.$column }
            }

            if ($existing.ContainsKey($groupNameInRealm)) {
                $null = Invoke-FreeIPARequest -Method 'pwpolicy_mod' -Arguments $groupNameInRealm -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedPolicies++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'pwpolicy_add' -Arguments $groupNameInRealm -Options $options -Connection $connection
                $result.CreatedPolicies++
                Write-Verbose "Created password policy for $groupNameInRealm"
            }
            $policies.Add([PSCustomObject]@{ Key = $row.Group; Group = $groupNameInRealm; Priority = $row.Priority })
        }
        catch {
            $message = "Failed to create the password policy for '$groupNameInRealm': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Policies = $policies.ToArray()
    Write-Verbose "Password policies: $($result.CreatedPolicies) created, $($result.UpdatedPolicies) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
