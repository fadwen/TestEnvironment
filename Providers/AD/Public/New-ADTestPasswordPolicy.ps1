function New-ADTestPasswordPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded fine-grained password policies from Data\ADPasswordPolicies.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [switch]$PassThru
    )

    $seed = Get-ADTestSeedMarker

    $csvPath = Join-Path -Path (Get-ADTestDataPath) -ChildPath 'ADPasswordPolicies.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($PolicyName) {
        $rows = @($rows | Where-Object { $PolicyName -contains $_.Name })
        $unknown = @($PolicyName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalPolicies   = $rows.Count
        CreatedPolicies = 0
        UpdatedPolicies = 0
        SubjectsApplied = 0
        Policies        = @()
        Errors          = @()
    }

    # A day count of zero means "never" for both an age and a lockout, and that is the value
    # the directory stores, so it is passed through rather than treated as absent.
    $days = { param($value) [TimeSpan]::FromDays([int]$value) }
    $minutes = { param($value) [TimeSpan]::FromMinutes([int]$value) }

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $seed.Prefix, $row.Name
        $groupName = '{0}{1}' -f $seed.Prefix, $row.AppliesToGroup
        if (-not $PSCmdlet.ShouldProcess($name, 'Create AD fine-grained password policy')) { continue }

        try {
            $settings = @{
                Precedence                  = [int]$row.Precedence
                MinPasswordLength           = [int]$row.MinPasswordLength
                MaxPasswordAge              = & $days $row.MaxPasswordAgeDays
                MinPasswordAge              = & $days $row.MinPasswordAgeDays
                PasswordHistoryCount        = [int]$row.HistoryCount
                ComplexityEnabled           = ($row.ComplexityEnabled -eq 'TRUE')
                ReversibleEncryptionEnabled = ($row.ReversibleEncryption -eq 'TRUE')
                LockoutThreshold            = [int]$row.LockoutThreshold
                LockoutObservationWindow    = & $minutes $row.LockoutWindowMinutes
                LockoutDuration             = & $minutes $row.LockoutDurationMinutes
            }

            $existing = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$($name.Replace("'", "''"))'" -ErrorAction SilentlyContinue
            if ($existing) {
                Set-ADFineGrainedPasswordPolicy -Identity $existing.DistinguishedName @settings -ErrorAction Stop
                $result.UpdatedPolicies++
                Write-Verbose "Updated password policy $name"
            }
            else {
                # Protection off on purpose: a protected object cannot be deleted without
                # clearing the flag first, and this module has to be able to remove what it made.
                $null = New-ADFineGrainedPasswordPolicy -Name $name @settings `
                    -Description $row.Purpose `
                    -ProtectedFromAccidentalDeletion $false `
                    -OtherAttributes @{ adminDescription = $seed.Tag } `
                    -ErrorAction Stop
                $result.CreatedPolicies++
                Write-Verbose "Created password policy $name"
            }

            # The subject is the seeded group. A policy applied to nothing governs nobody,
            # so a group that is missing is an error on the row rather than a silent pass.
            $group = Get-ADGroup -Filter "Name -eq '$($groupName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
            if ($group) {
                Add-ADFineGrainedPasswordPolicySubject -Identity $name -Subjects $group.DistinguishedName -ErrorAction Stop
                $result.SubjectsApplied++
            }
            else {
                $message = "Password policy '$name' names the group '$groupName', which does not exist. Applied to nobody."
                $result.Errors += $message
                Write-Error $message
            }

            $result.Policies += [PSCustomObject]@{
                Key        = $row.Name
                Name       = $name
                Precedence = [int]$row.Precedence
                AppliesTo  = $groupName
            }
        }
        catch {
            $message = "Failed to create password policy '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-Verbose ("Password policies: $($result.CreatedPolicies) created, $($result.UpdatedPolicies) updated, " +
        "$($result.SubjectsApplied) applied, $($result.Errors.Count) problems")
    if ($PassThru) { return $result }
}
