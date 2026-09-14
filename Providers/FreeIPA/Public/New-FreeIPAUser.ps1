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
        ManagersApplied    = 0
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
    # Decided row by row, sent in batches. FreeIPA's JSON-RPC batch method carries many
    # commands in one round trip, and the round trip was where the seed's time went: 357
    # users one call each was ten minutes of waiting on the wire. Each row is still decided,
    # confirmed and reported one at a time; only the sending is shared.
    $plans = [System.Collections.Generic.List[object]]::new()
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
            # Where a radius or idp authentication type authenticates: a seeded proxy or
            # provider, by its realm name, and the login the user has there.
            if ($row.RadiusProxy) { $options['ipatokenradiusconfiglink'] = Resolve-FreeIPASeedName -Key $row.RadiusProxy -Marker $marker -Connection $connection }
            if ($row.RadiusUsername) { $options['ipatokenradiususername'] = $row.RadiusUsername }
            if ($row.IdentityProvider) { $options['ipaidpconfiglink'] = Resolve-FreeIPASeedName -Key $row.IdentityProvider -Marker $marker -Connection $connection }
            if ($row.IdpUserId) { $options['ipaidpsub'] = $row.IdpUserId }
            if ($row.SshPublicKeys) { $options['ipasshpubkey'] = [object[]]@(& $split $row.SshPublicKeys) }
            if ($row.PrincipalExpiresInDays -match '^-?\d+$') {
                $options['krbprincipalexpiration'] = ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::UtcNow.AddDays([int]$row.PrincipalExpiresInDays))
            }

            $isStaged = $row.Lifecycle -eq 'Staged'
            $isPreserved = $row.Lifecycle -eq 'Preserved'
            $isDisabled = $row.Lifecycle -eq 'Disabled'
            # The plan says which command this row needs; the commands go below, in batches.
            $plan = [PSCustomObject]@{
                Row = $row; Login = $login; Method = $null; Options = $options; IgnoreError = @()
                Outcome = $null; Temporary = $null; IsStaged = $isStaged; IsDisabled = $isDisabled
                LeftPreserved = $false; Preserve = ($isPreserved -and -not $existingPreserved.ContainsKey($login))
            }
            if ($isStaged) {
                if ($existingStaged.ContainsKey($login)) { $plan.Method = 'stageuser_mod'; $plan.IgnoreError = @('EmptyModlist'); $plan.Outcome = 'Updated' }
                else { $plan.Method = 'stageuser_add'; $plan.Outcome = 'Created' }
            }
            elseif ($existingPreserved.ContainsKey($login)) {
                # Already preserved. Every membership is gone and the entry is the audit trail;
                # re-adding would mean un-preserving, which is not what a re-run means.
                $plan.LeftPreserved = $true
                $plan.Outcome = 'Updated'
            }
            elseif ($existingActive.ContainsKey($login)) {
                $plan.Method = 'user_mod'; $plan.IgnoreError = @('EmptyModlist'); $plan.Outcome = 'Updated'
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
                if ($plainPassword -and $row.PasswordState -eq 'MustChange') { $options['userpassword'] = $plainPassword }
                elseif ($plainPassword -and $row.PasswordState -eq 'Current') {
                    $plan.Temporary = New-TestPassword -Length 24
                    $options['userpassword'] = $plan.Temporary
                }
                $plan.Method = 'user_add'; $plan.Outcome = 'Created'
            }
            $plans.Add($plan)
        }
        catch {
            $message = "Failed to create user '$login': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    Write-TestProgress -Activity 'Seeding users' -Completed -ShowProgress:$ShowProgress

    # The primary command for every row, fifty to a request. A row the realm refused fails alone
    # and takes no further part; its message is recorded as it was when the calls were one each.
    $failed = @{}
    $primary = @($plans | Where-Object { $_.Method })
    if ($primary.Count -gt 0) {
        $commands = @($primary | ForEach-Object { @{ Method = $_.Method; Arguments = @($_.Login); Options = $_.Options; IgnoreError = $_.IgnoreError; Tag = $_.Login } })
        foreach ($answer in @(Invoke-FreeIPABatch -Command $commands -Connection $connection)) {
            if ($answer.Success) { continue }
            $failed[[string]$answer.Command.Tag] = $true
            $message = "Failed to create user '$($answer.Command.Tag)': $($answer.ErrorMessage)"
            $result.Errors += $message
            Write-Error $message
        }
    }
    $done = @($plans | Where-Object { -not $failed.ContainsKey($_.Login) })
    foreach ($plan in $done) {
        if ($plan.Outcome -eq 'Created') { $result.CreatedUsers++; Write-Verbose "Created user $($plan.Login)" }
        else { $result.UpdatedUsers++; Write-Verbose "Updated user $($plan.Login)" }
        if ($plan.IsStaged) { $result.StagedUsers++ }
        if ($plan.LeftPreserved) { $result.PreservedUsers++; Write-Verbose "Left $($plan.Login) preserved" }
    }

    # Passwords. MustChange went with the add and is already what an admin-set password is.
    # Current is changed as the user, one call each, because the change endpoint is a form the
    # user posts rather than a command an administrator can batch.
    foreach ($plan in @($done | Where-Object { $_.Method -eq 'user_add' -and $_.Options.ContainsKey('userpassword') })) {
        try {
            if ($plan.Temporary) {
                Set-FreeIPAPassword -Connection $connection -Username $plan.Login -OldPassword $plan.Temporary -NewPassword $plainPassword -Confirm:$false
            }
            $result.PasswordsSet++
        }
        catch {
            $message = "Failed to set the password of '$($plan.Login)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    # Certificate mapping data and the disabled state, batched the same way.
    $follow = [System.Collections.Generic.List[object]]::new()
    foreach ($plan in $done) {
        if ($plan.Method -eq 'user_add' -and $plan.Row.CertMapData) {
            $issuer, $subject = $plan.Row.CertMapData -split '\|'
            $follow.Add(@{ Method = 'user_add_certmapdata'; Arguments = @($plan.Login); Options = @{ issuer = $issuer; subject = $subject }; Tag = "add certificate mapping data to '$($plan.Login)'"; Disables = $false })
        }
        if ($plan.IsDisabled -and -not $plan.IsStaged -and -not $plan.LeftPreserved) {
            $follow.Add(@{ Method = 'user_disable'; Arguments = @($plan.Login); Options = @{}; IgnoreError = @('AlreadyInactive'); Tag = "disable '$($plan.Login)'"; Disables = $true })
        }
    }
    if ($follow.Count -gt 0) {
        foreach ($answer in @(Invoke-FreeIPABatch -Command $follow.ToArray() -Connection $connection)) {
            if ($answer.Success) {
                if ($answer.Command.Disables) { $result.DisabledUsers++ }
                continue
            }
            $message = "Failed to $($answer.Command.Tag): $($answer.ErrorMessage)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    foreach ($plan in $done) {
        $row = $plan.Row
        if (-not $plan.IsStaged -and -not $plan.LeftPreserved -and -not $SkipGroups) {
            foreach ($groupKey in (& $split $row.Groups)) {
                if (-not $membersOf.ContainsKey($groupKey)) { $membersOf[$groupKey] = [System.Collections.Generic.List[string]]::new() }
                $membersOf[$groupKey].Add($plan.Login)
            }
        }
        $users.Add([PSCustomObject]@{
                Username  = $plan.Login
                Name      = $row.DisplayName
                Lifecycle = $row.Lifecycle
                Class     = $row.Class
                Groups    = @(& $split $row.Groups)
                Preserve  = $plan.Preserve
            })
    }
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

    # The member managers the groups file names by login. New-FreeIPAGroup runs before any
    # user exists, so the users it could not name as managers are applied here, for the
    # users this run processed; a manager outside the selection is left for a fuller run.
    if (-not $SkipGroups) {
        $processed = @($users | ForEach-Object { $_.Username })
        $groupRows = @(Import-Csv -Path (Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAGroups.csv') -Encoding UTF8)
        foreach ($groupRow in ($groupRows | Where-Object { $_.ManagerUsers })) {
            $managers = @(& $split $groupRow.ManagerUsers | Where-Object { $processed -contains $_ })
            if ($managers.Count -eq 0) { continue }
            $groupName = Resolve-FreeIPASeedName -Key $groupRow.Name -Marker $marker -Connection $connection
            if (-not $PSCmdlet.ShouldProcess($groupName, "Add $($managers.Count) member manager(s)")) { continue }
            $added = Add-FreeIPAMember -Method 'group_add_member_manager' -Name $groupName -Members @{ user = $managers } -Connection $connection
            $result.ManagersApplied += $added.Completed
            foreach ($problem in $added.Errors) {
                $result.Errors += "Group '$groupName': $problem"
                Write-Error "Group '$groupName': $problem"
            }
        }
    }

    # Preserving last, after the memberships it strips, in one batch.
    $preserving = @($users | Where-Object { $_.Preserve -and $PSCmdlet.ShouldProcess($_.Username, 'Preserve FreeIPA user') })
    if ($preserving.Count -gt 0) {
        $commands = @($preserving | ForEach-Object { @{ Method = 'user_del'; Arguments = @($_.Username); Options = @{ preserve = $true }; Tag = $_.Username } })
        foreach ($answer in @(Invoke-FreeIPABatch -Command $commands -Connection $connection)) {
            if ($answer.Success) { $result.PreservedUsers++; Write-Verbose "Preserved user $($answer.Command.Tag)"; continue }
            $message = "Failed to preserve user '$($answer.Command.Tag)': $($answer.ErrorMessage)"
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
