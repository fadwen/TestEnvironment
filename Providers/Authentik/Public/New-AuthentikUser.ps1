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
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$SkipGroups,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikUsers.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

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

    foreach ($row in $rows) {
        $email = '{0}@{1}' -f $row.Username, $connection.EmailDomain

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

            $user = $null
            if ($existingByUsername.ContainsKey($row.Username)) {
                $user = Invoke-AuthentikRequest -Method PATCH -Path "/core/users/$($existingByUsername[$row.Username].pk)/" -Body $body -Connection $connection
                $result.UpdatedUsers++
                Write-Verbose "Updated user $($row.Username)"
            }
            else {
                $user = Invoke-AuthentikRequest -Method POST -Path '/core/users/' -Body $body -Connection $connection
                $result.CreatedUsers++
                Write-Verbose "Created user $($row.Username)"
            }

            if ($plainPassword) {
                $null = Invoke-AuthentikRequest -Method POST -Path "/core/users/$($user.pk)/set_password/" `
                    -Body @{ password = $plainPassword } -Connection $connection
                $result.PasswordsSet++
            }

            $users.Add([PSCustomObject]@{
                    Id         = [int]$user.pk
                    Username   = $row.Username
                    Name       = $row.Name
                    Email      = $email
                    Type       = $row.Type
                    IsActive   = ($row.IsActive -eq 'TRUE')
                    Groups     = @($row.Groups -split ';' | Where-Object { $_ })
                    Contractor = ($row.LabIsContractor -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create user '$($row.Username)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Users = $users.ToArray()

    Write-Verbose ("Users: $($result.CreatedUsers) created, $($result.UpdatedUsers) updated, " +
        "$($result.PasswordsSet) passwords set, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
