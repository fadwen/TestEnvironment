function New-OneLoginMfaFactor {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Pre-enrols the seeded people's MFA factors, where the account already offers the factor
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Username,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginUsers.csv') -Encoding UTF8 | Where-Object { $_.Mfa })
    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($Username) { $rows = @($rows | Where-Object { $Username -contains $_.Key }) }

    # Proved seeded people only. A factor is enrolled on nobody else, and only ever already verified,
    # so no code is sent anywhere - and a seeded address is at the lab domain, which cannot receive.
    $seededByLogin = @{}
    foreach ($user in @(Get-OneLoginSeededObject -Type Users -Connection $connection)) { $seededByLogin[([string]$user.username).ToLowerInvariant()] = $user }

    $enrolled = [System.Collections.Generic.List[object]]::new()
    $existing = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        $login = Resolve-OneLoginSeedName -Key $row.Key -Kind Username -Connection $connection
        $user = $seededByLogin[$login.ToLowerInvariant()]
        if (-not $user) { $errors.Add("$login is not seeded; run New-OneLoginUser first"); continue }

        # Which factors the account offers this person. The seed does not turn a factor on: that is an
        # account-wide setting, and changing it would change what every real person is offered.
        $available = @(Invoke-OneLoginRequest -Method GET -Path "mfa/users/$($user.id)/factors" -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
        $factor = @($available | Where-Object { ([string]$_.name -like "*$($row.Mfa)*") -or ([string]$_.auth_factor_name -like "*$($row.Mfa)*") }) | Select-Object -First 1
        if (-not $factor) {
            $skipped.Add(("{0}: the account offers no {1} factor. Enable OneLogin {1} under Authentication Factors, and allow it in the user's policy, to seed it." -f $login, $row.Mfa))
            continue
        }

        $devices = @(Invoke-OneLoginRequest -Method GET -Path "mfa/users/$($user.id)/devices" -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
        if (@($devices | Where-Object { ([string]$_.auth_factor_name -like "*$($row.Mfa)*") -or ([string]$_.type_display_name -like "*$($row.Mfa)*") })) {
            $existing.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Factor = $row.Mfa })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$login : $($row.Mfa)", 'Enrol a verified OneLogin MFA factor')) { continue }
        try {
            $null = Invoke-OneLoginRequest -Method POST -Path "mfa/users/$($user.id)/registrations" -Connection $connection -Body @{
                factor_id    = $factor.factor_id
                display_name = Resolve-OneLoginSeedName -Key $row.Mfa -Kind DisplayName -Connection $connection
                verified     = $true
            }
            $enrolled.Add([PSCustomObject]@{ Key = $row.Key; Username = $login; Factor = $row.Mfa })
        }
        catch { $errors.Add("Could not enrol $($row.Mfa) for ${login}: $($_.Exception.Message)") }
    }

    if ($skipped.Count -gt 0) {
        Write-Verbose ("MFA factors not seeded: {0}" -f ($skipped -join '; '))
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalFactors    = @($rows).Count
            EnrolledFactors = $enrolled.Count
            ExistingFactors = $existing.Count
            Skipped         = $skipped.ToArray()
            Factors         = (@($enrolled) + @($existing))
            Errors          = $errors.ToArray()
        }
    }
}
