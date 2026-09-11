function New-FreeIPAUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded FreeIPA users from Data\FreeIPAUsers.csv, in their groups and lifecycle states
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

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAUsers.csv'
    $allRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $rows = $allRows

    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }
    if ($UserName) {
        $rows = @($allRows | Where-Object { $UserName -contains $_.Username })
        $unknown = @($UserName | Where-Object { $rows.Username -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    # Managers first. A manager has to exist before the person who reports to them, so the
    # rows are ordered by the length of the chain above them, from the full CSV so a partial
    # selection keeps the same order.
    $managerOf = @{}
    foreach ($row in $allRows) { $managerOf[$row.Username] = $row.Manager }
    $depthOf = {
        param($key)
        $depth = 0
        $current = $managerOf[$key]
        while ($current -and $depth -lt 50) { $depth++; $current = $managerOf[$current] }
        $depth
    }
    $rows = @($rows | Sort-Object -Property @{ Expression = { & $depthOf $_.Username } }, Username)

    $result = [PSCustomObject]@{
        TotalUsers         = $rows.Count
        CreatedUsers       = 0
        UpdatedUsers       = 0
        StagedUsers        = 0
        PreservedUsers     = 0
        DisabledUsers      = 0
        PasswordsSet       = 0
        MembershipsApplied = 0
        Users              = @()
        Errors             = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }

    $existingActive = @{}
    foreach ($user in (Get-FreeIPASeededObject -Type Users -Connection $connection)) { $existingActive[[string](@($user.uid)[0])] = $user }
    $existingStaged = @{}
    foreach ($user in (Get-FreeIPASeededObject -Type StagedUsers -Connection $connection)) { $existingStaged[[string](@($user.uid)[0])] = $user }
    $existingPreserved = @{}
    foreach ($user in (Get-FreeIPASeededObject -Type PreservedUsers -Connection $connection)) { $existingPreserved[[string](@($user.uid)[0])] = $user }

    $plainPassword = $null
    if ($AccountPassword) { $plainPassword = ConvertFrom-TestSecureString -SecureString $AccountPassword }

    # The GID a user with no private group takes: that of a seeded POSIX group, read once.
    $gidByGroupKey = @{}

    $users = [System.Collections.Generic.List[object]]::new()
    $membersOf = @{}
    $index = 0

    foreach ($row in $rows) {
        $login = $row.Username
        $index++
        Write-TestProgress -Activity 'Seeding users' -Status "$index of $($rows.Count): $login" `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $rows.Count))) -ShowProgress:$ShowProgress

        if (-not $PSCmdlet.ShouldProcess("$($row.DisplayName) ($login, $($row.Lifecycle))", 'Create FreeIPA user')) { continue }

        try {
            $options = @{
                givenname   = $row.GivenName
                sn          = $row.Surname
                cn          = $row.DisplayName
                displayname = $row.DisplayName
                userclass   = [object[]]@(@($marker.Tag) + @(& $split $row.Class))
                loginshell  = $row.LoginShell
            }
            if ($row.Title) { $options['title'] = $row.Title }
            if ($row.OrgUnit) { $options['ou'] = $row.OrgUnit }
            if ($row.Manager) { $options['manager'] = $row.Manager }
            if ($row.EmployeeNumber) { $options['employeenumber'] = $row.EmployeeNumber }
            if ($row.EmployeeType) { $options['employeetype'] = $row.EmployeeType }
            if ($row.HomeDirectory) { $options['homedirectory'] = $row.HomeDirectory }
            if ($row.Phone) { $options['telephonenumber'] = [object[]]@($row.Phone) }
            if ($row.Mobile) { $options['mobile'] = [object[]]@($row.Mobile) }
            if ($row.Street) { $options['street'] = $row.Street }
            if ($row.City) { $options['l'] = $row.City }
            if ($row.State) { $options['st'] = $row.State }
            if ($row.PostalCode) { $options['postalcode'] = $row.PostalCode }
            if ($row.PreferredLanguage) { $options['preferredlanguage'] = $row.PreferredLanguage }
            if ($row.UserAuthType) { $options['ipauserauthtype'] = [object[]]@(& $split $row.UserAuthType) }
            if ($row.SshPublicKeys) { $options['ipasshpubkey'] = [object[]]@(& $split $row.SshPublicKeys) }
            if ($row.PrincipalExpiresInDays -match '^-?\d+$') {
                $options['krbprincipalexpiration'] = ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::UtcNow.AddDays([int]$row.PrincipalExpiresInDays))
            }

            $isStaged = $row.Lifecycle -eq 'Staged'
            $isPreserved = $row.Lifecycle -eq 'Preserved'
            $isDisabled = $row.Lifecycle -eq 'Disabled'
            $stateSet = $false

            if ($isStaged) {
                if ($existingStaged.ContainsKey($login)) {
                    $null = Invoke-FreeIPARequest -Method 'stageuser_mod' -Arguments $login -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                    $result.UpdatedUsers++
                }
                else {
                    $null = Invoke-FreeIPARequest -Method 'stageuser_add' -Arguments $login -Options $options -Connection $connection
                    $result.CreatedUsers++
                }
                $result.StagedUsers++
                $stateSet = $true
            }
            elseif ($existingPreserved.ContainsKey($login)) {
                # Already preserved. Every membership is gone and the entry is the audit trail;
                # re-adding would mean un-preserving, which is not what a re-run means.
                $result.UpdatedUsers++
                $result.PreservedUsers++
                $stateSet = $true
                Write-Verbose "Left $login preserved"
            }
            elseif ($existingActive.ContainsKey($login)) {
                $null = Invoke-FreeIPARequest -Method 'user_mod' -Arguments $login -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedUsers++
                Write-Verbose "Updated user $login"
            }
            else {
                if ($row.NoPrivateGroup -eq 'TRUE') {
                    $groupKey = $row.PrimaryGroup
                    if (-not $gidByGroupKey.ContainsKey($groupKey)) {
                        $groupName = Resolve-FreeIPASeedName -Key $groupKey -Marker $marker -Connection $connection
                        $shown = Invoke-FreeIPARequest -Method 'group_show' -Arguments $groupName -Connection $connection
                        $gidByGroupKey[$groupKey] = [int](@($shown.result.gidnumber)[0])
                    }
                    $options['noprivate'] = $true
                    $options['gidnumber'] = $gidByGroupKey[$groupKey]
                }

                $temporary = $null
                if ($plainPassword -and $row.PasswordState -eq 'MustChange') { $options['userpassword'] = $plainPassword }
                elseif ($plainPassword -and $row.PasswordState -eq 'Current') {
                    $temporary = New-TestPassword -Length 24
                    $options['userpassword'] = $temporary
                }

                $null = Invoke-FreeIPARequest -Method 'user_add' -Arguments $login -Options $options -Connection $connection
                $result.CreatedUsers++
                Write-Verbose "Created user $login"

                if ($options.ContainsKey('userpassword')) {
                    if ($temporary) {
                        # Changed as the user, which is the one route to a password that is
                        # current rather than expired-on-arrival.
                        Set-FreeIPAPassword -Connection $connection -Username $login -OldPassword $temporary -NewPassword $plainPassword -Confirm:$false
                    }
                    $result.PasswordsSet++
                }

                if ($row.CertMapData) {
                    $issuer, $subject = $row.CertMapData -split '\|'
                    $null = Invoke-FreeIPARequest -Method 'user_add_certmapdata' -Arguments $login -Connection $connection `
                        -Options @{ issuer = $issuer; subject = $subject }
                }
            }

            if (-not $stateSet -and $isDisabled) {
                $null = Invoke-FreeIPARequest -Method 'user_disable' -Arguments $login -Connection $connection -IgnoreError 'AlreadyInactive'
                $result.DisabledUsers++
            }

            if (-not $isStaged -and -not $existingPreserved.ContainsKey($login) -and -not $SkipGroups) {
                foreach ($groupKey in (& $split $row.Groups)) {
                    if (-not $membersOf.ContainsKey($groupKey)) { $membersOf[$groupKey] = [System.Collections.Generic.List[string]]::new() }
                    $membersOf[$groupKey].Add($login)
                }
            }

            $users.Add([PSCustomObject]@{
                    Username  = $login
                    Name      = $row.DisplayName
                    Lifecycle = $row.Lifecycle
                    Class     = $row.Class
                    Groups    = @(& $split $row.Groups)
                    Preserve  = ($isPreserved -and -not $existingPreserved.ContainsKey($login))
                })
        }
        catch {
            $message = "Failed to create user '$login': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-TestProgress -Activity 'Seeding users' -Completed -ShowProgress:$ShowProgress

    # Membership, one call per group. The users to be preserved are members here, so that
    # preserving strips something, which is the state the row describes.
    foreach ($groupKey in ($membersOf.Keys | Sort-Object)) {
        $groupName = Resolve-FreeIPASeedName -Key $groupKey -Marker $marker -Connection $connection
        $members = @($membersOf[$groupKey])
        if (-not $PSCmdlet.ShouldProcess($groupName, "Add $($members.Count) member user(s)")) { continue }
        for ($start = 0; $start -lt $members.Count; $start += 100) {
            $chunk = @($members[$start..([Math]::Min($start + 99, $members.Count - 1))])
            try {
                $outcome = Invoke-FreeIPARequest -Method 'group_add_member' -Arguments $groupName -Connection $connection `
                    -Options @{ user = [object[]]$chunk }
                $result.MembershipsApplied += [int]$outcome.completed
                foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
                    if ($failure -like '*already a member*') { continue }
                    $message = "Could not add to group '$groupName': $failure"
                    $result.Errors += $message
                    Write-Error $message
                }
            }
            catch {
                $message = "Failed to add members to group '$groupName': $($_.Exception.Message)"
                $result.Errors += $message
                Write-Error $message
            }
        }
    }

    # Preserving last, after the memberships it strips.
    foreach ($user in ($users | Where-Object { $_.Preserve })) {
        if (-not $PSCmdlet.ShouldProcess($user.Username, 'Preserve FreeIPA user')) { continue }
        try {
            $null = Invoke-FreeIPARequest -Method 'user_del' -Arguments $user.Username -Options @{ preserve = $true } -Connection $connection
            $result.PreservedUsers++
            Write-Verbose "Preserved user $($user.Username)"
        }
        catch {
            $message = "Failed to preserve user '$($user.Username)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Users = @($users | Select-Object -Property Username, Name, Lifecycle, Class, Groups)

    Write-Verbose ("Users: $($result.CreatedUsers) created, $($result.UpdatedUsers) updated, $($result.StagedUsers) staged, " +
        "$($result.PreservedUsers) preserved, $($result.DisabledUsers) disabled, $($result.PasswordsSet) passwords set, " +
        "$($result.MembershipsApplied) memberships, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
