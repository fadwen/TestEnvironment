function New-AuthentikUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Authentik users from Data\AuthentikUsers.csv, in their groups
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$UserName,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$SkipGroups,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikUsers.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($UserName) {
        $rows = @($rows | Where-Object { $UserName -contains $_.Username })
        $unknown = @($UserName | Where-Object { $rows.Username -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalUsers   = $rows.Count
        CreatedUsers = 0
        UpdatedUsers = 0
        PasswordsSet = 0
        Users        = @()
        Errors       = @()
    }

    $groupPkByKey = @{}
    if (-not $SkipGroups) {
        foreach ($group in (Get-AuthentikSeededObject -Type Groups -Connection $connection)) {
            if ($group.attributes.PSObject.Properties['labKey']) { $groupPkByKey[[string]$group.attributes.labKey] = [string]$group.pk }
        }
    }

    $existingByUsername = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Users -Connection $connection)) {
        $existingByUsername[[string]$existing.username] = $existing
    }

    $plainPassword = $null
    if ($AccountPassword) { $plainPassword = ConvertFrom-TestSecureString -SecureString $AccountPassword }

    $users = [System.Collections.Generic.List[object]]::new()
    # Decided row by row, created several at a time. The instance answers one request in about
    # a second and has no batch endpoint, so 330 users one call each was the seed's time; the
    # workers wait on four at once. Each row is still confirmed and reported one at a time, here.
    $plans = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($row in $rows) {
        $email = '{0}@{1}' -f $row.Username, $connection.EmailDomain
        $index++
        Write-TestProgress -Activity 'Seeding users' -Status "$index of $($rows.Count): $($row.Username)" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess("$($row.Name) <$email>", 'Create Authentik user')) { continue }

        try {
            $groups = @()
            if (-not $SkipGroups) {
                foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) {
                    if ($groupPkByKey.ContainsKey($key)) { $groups += $groupPkByKey[$key] }
                    else {
                        $message = "User '$($row.Username)' lists group '$key', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                    }
                }
            }

            $entitlements = @($row.LabEntitlements -split ';' | Where-Object { $_ })
            $attributes = [ordered]@{}
            $attributes[$marker.Attribute] = $marker.Tag
            $attributes['labKey'] = $row.Username
            $attributes['labTitle'] = $row.Title
            $attributes['labDepartment'] = $row.Department
            $attributes['labManager'] = $row.Manager
            $attributes['labBadgeId'] = $row.LabBadgeId
            $attributes['labClearanceLevel'] = $row.LabClearanceLevel
            $attributes['labIsContractor'] = ($row.LabIsContractor -eq 'TRUE')
            $attributes['labRiskScore'] = $(if ($row.LabRiskScore -match '^\d+$') { [int]$row.LabRiskScore } else { 0 })
            $attributes['labEntitlements'] = $entitlements

            $body = @{
                username   = $row.Username
                name       = $row.Name
                email      = $email
                is_active  = ($row.IsActive -eq 'TRUE')
                type       = $row.Type
                path       = $marker.UserPath
                groups     = $groups
                attributes = $attributes
            }

            $existingPk = $null
            if ($existingByUsername.ContainsKey($row.Username)) { $existingPk = [string]$existingByUsername[$row.Username].pk }
            $plans.Add([PSCustomObject]@{ Row = $row; Email = $email; Body = $body; ExistingPk = $existingPk })
        }
        catch {
            $message = "Failed to create user '$($row.Username)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }
    Write-TestProgress -Activity 'Seeding users' -Completed -ShowProgress:$ShowProgress

    # The workers get the connection and the password through -Parameter and nothing else; a
    # worker runspace has the module's functions and none of the session's state.
    $answers = @(Invoke-TestParallel -InputObject $plans.ToArray() -Activity 'Creating users' -ShowProgress:$ShowProgress `
            -Parameter @{ Connection = $connection; Password = $plainPassword } -ScriptBlock {
            param($Item, $Parameter)
            $user = if ($Item.ExistingPk) {
                Invoke-AuthentikRequest -Method PATCH -Path "/core/users/$($Item.ExistingPk)/" -Body $Item.Body -Connection $Parameter.Connection
            }
            else {
                Invoke-AuthentikRequest -Method POST -Path '/core/users/' -Body $Item.Body -Connection $Parameter.Connection
            }
            $passwordSet = $false
            if ($Parameter.Password) {
                $null = Invoke-AuthentikRequest -Method POST -Path "/core/users/$($user.pk)/set_password/" `
                    -Body @{ password = $Parameter.Password } -Connection $Parameter.Connection
                $passwordSet = $true
            }
            [PSCustomObject]@{ Pk = [int]$user.pk; PasswordSet = $passwordSet }
        })
    foreach ($answer in $answers) {
        $plan = $answer.Input
        if (-not $answer.Success) {
            $message = "Failed to create user '$($plan.Row.Username)': $($answer.Error)"
            $result.Errors += $message
            Write-Error $message
            continue
        }
        $made = @($answer.Output)[-1]
        if ($plan.ExistingPk) { $result.UpdatedUsers++; Write-Verbose "Updated user $($plan.Row.Username)" }
        else { $result.CreatedUsers++; Write-Verbose "Created user $($plan.Row.Username)" }
        if ($made.PasswordSet) { $result.PasswordsSet++ }
        $users.Add([PSCustomObject]@{
                Id         = [int]$made.Pk
                Username   = $plan.Row.Username
                Name       = $plan.Row.Name
                Email      = $plan.Email
                Type       = $plan.Row.Type
                IsActive   = ($plan.Row.IsActive -eq 'TRUE')
                Groups     = @($plan.Row.Groups -split ';' | Where-Object { $_ })
                Contractor = ($plan.Row.LabIsContractor -eq 'TRUE')
            })
    }
    $result.Users = $users.ToArray()
    Write-Verbose ("Users: $($result.CreatedUsers) created, $($result.UpdatedUsers) updated, " +
        "$($result.PasswordsSet) passwords set, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
