function New-ADTestSecurityGroups {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates Active Directory test security groups from CSV data
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = 'Job blocks take param() and bind by -ArgumentList; Using: does not apply.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Exported name; renaming it would break callers.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$SkipMemberAssignment,

        [ValidateRange(1, 50)]
        [int]$BatchSize = 15,

        [ValidateRange(1, 20)]
        [int]$ThrottleLimit = 5,

        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestSecurityGroups - CorrelationId: $correlationId"

        # Get data paths
        $dataPath = Get-ADTestDataPath
        $groupsCSV = Join-Path $dataPath "ADSecurityGroups.csv"

        # Verify prerequisites
        if (-not (Test-Path $groupsCSV)) {
            throw "ADSecurityGroups.csv not found at: $groupsCSV"
        }

        # Get domain information
        $domain = Get-ADTestDomain

        # Counters
        $script:GroupsCreated = 0
        $script:GroupsSkipped = 0
        $script:MembersAdded = 0
        $script:GroupsNested = 0
        $script:Errors = @()

        # Job tracking for batch processing
        $script:MembershipJobs = [System.Collections.Generic.List[object]]::new()
        $script:JobResults = [System.Collections.Generic.List[object]]::new()
    }

    process {
        try {
            Write-TestMessage -Message "Creating Active Directory Test Security Groups" -Type Header
            Write-TestMessage -Message "Loading security group data from CSV..." -Type Info

            # Import group data
            $groups = Import-Csv $groupsCSV
            Write-Verbose "Loaded $($groups.Count) groups from CSV"

            $totalGroups = $groups.Count
            $currentGroup = 0

            Write-TestMessage -Message "Processing $totalGroups security groups..." -Type Info

            foreach ($group in $groups) {
                $currentGroup++
                $percentComplete = ($currentGroup / $totalGroups) * 80  # Reserve 20% for member assignment

                $progressParams = @{
                    Activity        = 'Creating Security Groups'
                    Status          = "Processing $($group.GroupName)"
                    PercentComplete = $percentComplete
                }
                Write-Progress @progressParams

                try {
                    # Skip if group already exists
                    $groupFilter = "Name -eq '$((Get-ADTestSeedMarker).Prefix)$($group.GroupName)'"
                    $existingGroup = Get-ADGroup -Filter $groupFilter -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Write-Verbose "Group $($group.GroupName) already exists, skipping"
                        $script:GroupsSkipped++
                        continue
                    }

                    # Determine OU path based on category
                    $ouPath = switch ($group.Category) {
                        'Administrative' { "OU=Administrative,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Access Control' { "OU=Resource,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Departmental' { "OU=Department,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Device Access' { "OU=Device,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Application Access' { "OU=Resource,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Employment Type' { "OU=Role,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Geographic' { "OU=Location,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Management Level' { "OU=Role,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Organizational' { "OU=Role,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Physical Access' { "OU=Resource,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        'Resource Access' { "OU=Resource,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                        default { "OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)" }
                    }

                    # Verify OU exists, skip group creation if not found
                    try {
                        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Warning ("OU not found: $ouPath. Skipping group creation " +
                            "for $($group.GroupName). Please ensure OU structure is " +
                            'created first.')
                        $script:GroupsSkipped++
                        continue
                    }                    # Map group scope
                    $groupScope = switch ($group.GroupScope) {
                        'DomainLocal' { 'DomainLocal' }
                        'Global' { 'Global' }
                        'Universal' { 'Universal' }
                        default { 'Global' }
                    }

                    # The seed prefix and the shared description tag. Groups take the prefix on
                    # both the name and the account name: a group's sAMAccountName is not capped
                    # at 20 the way a user's or a computer's is, verified against a live domain
                    # at 33 characters.
                    $seed = Get-ADTestSeedMarker
                    $prefixedName = '{0}{1}' -f $seed.Prefix, $group.GroupName

                    $groupParams = @{
                        Name = $prefixedName
                        SamAccountName = $prefixedName
                        GroupCategory = 'Security'
                        GroupScope = $groupScope
                        Path = $ouPath

                        # Description stays exactly what the CSV says. The seed tag lives in
                        # adminDescription instead - see the OtherAttributes note below.
                        Description = $group.Description
                        OtherAttributes = @{ adminDescription = $seed.Tag }
                    }

                    # mail and info, where the CSV supplies them. The Mail column carries the
                    # local part only and the domain is appended here - the same convention
                    # New-ADTestUser already uses, which keeps the shipped data free of any
                    # particular organisation's domain name.
                    # Added to the hashtable already holding adminDescription rather than
                    # replacing it. Assigning a fresh one here is what silently dropped the seed
                    # tag from the 59 groups whose CSV row supplies a Mail or Info value - they
                    # were created, correctly named and untagged, and only a per-class count
                    # showed it.
                    if ($group.Mail) {
                        $groupParams['OtherAttributes']['mail'] = "$($group.Mail)@$($domain.DNSName)"
                    }
                    if ($group.Info) {
                        $groupParams['OtherAttributes']['info'] = $group.Info
                    }

                    # ManagedBy holds a display name; the directory stores a distinguished
                    # name. New-ADEnvironment creates users before groups, so the owner
                    # exists by the time this runs. A leading CN= is tolerated because the
                    # sibling CSVs write owners that way.
                    if ($group.ManagedBy) {
                        $ownerName = $group.ManagedBy -replace '^CN=', ''
                        $ownerFilter = "Name -eq '$($ownerName.Replace("'", "''"))'"
                        $owner = Get-ADUser -Filter $ownerFilter -ErrorAction SilentlyContinue

                        if ($owner) {
                            $groupParams['ManagedBy'] = $owner.DistinguishedName
                        }
                        else {
                            Write-Warning ("Owner '$ownerName' not found for " +
                                "$($group.GroupName); ManagedBy left empty.")
                        }
                    }

                    # Create security group
                    if ($PSCmdlet.ShouldProcess($group.GroupName, "Create AD Security Group")) {
                        Write-Verbose "Creating security group: $($group.GroupName) in $ouPath"
                        New-ADGroup @groupParams
                        $script:GroupsCreated++
                    }
                    else {
                        $wouldCreate = 'Would create security group: ' +
                            "$($group.GroupName) in $ouPath"
                        Write-Host $wouldCreate -ForegroundColor Green
                    }
                }
                catch {
                    Write-Error "Failed to create group $($group.GroupName): $($_.Exception.Message)"
                    $script:Errors += "Group creation error for $($group.GroupName): $($_.Exception.Message)"
                }
            }

            # Second pass: group-into-group nesting from the MemberOfGroup column.
            #
            # Deliberately after the whole creation loop, because a group can be nested into
            # one that appears later in the file. Sequential rather than batched: it is a few
            # dozen writes, so it does not need the job machinery the user membership below
            # does, and keeping it in-process makes a nesting failure easy to attribute.
            #
            # Scope rules are the CSV's responsibility - Global may nest into any scope,
            # Universal into Universal or DomainLocal, DomainLocal into DomainLocal only. An
            # illegal pairing surfaces here as a per-row error rather than stopping the run.
            if (-not $SkipMemberAssignment -and -not $WhatIfPreference) {
                $nestingRow = @($groups | Where-Object { $_.MemberOfGroup })

                if ($nestingRow.Count -gt 0) {
                    $nestingMessage = "Nesting $($nestingRow.Count) group(s) into their " +
                        'parent groups...'
                    Write-TestMessage -Message $nestingMessage -Type Info

                    # Both sides of a nesting pair are looked up by their directory name, which
                    # carries the prefix. Comparing the bare CSV name reported all 38 pairs as
                    # "child not found" while the groups were sitting right there.
                    $nestPrefix = (Get-ADTestSeedMarker).Prefix

                    foreach ($row in $nestingRow) {
                        $childFilter = "Name -eq '$($nestPrefix)$($row.GroupName.Replace("'", "''"))'"
                        $child = Get-ADGroup -Filter $childFilter -ErrorAction SilentlyContinue

                        if (-not $child) {
                            $script:Errors += "Nesting skipped: child '$($row.GroupName)' not found"
                            continue
                        }

                        foreach ($parentName in ($row.MemberOfGroup -split ';')) {
                            $parentName = $parentName.Trim()

                            if (-not $parentName) {
                                continue
                            }

                            $parentFilter = "Name -eq '$($nestPrefix)$($parentName.Replace("'", "''"))'"
                            $parent = Get-ADGroup -Filter $parentFilter -ErrorAction SilentlyContinue

                            if (-not $parent) {
                                $script:Errors += "Nesting skipped: parent '$parentName' " +
                                    "not found for '$($row.GroupName)'"
                                continue
                            }

                            try {
                                Add-ADGroupMember -Identity $parent.DistinguishedName `
                                    -Members $child.DistinguishedName -ErrorAction Stop
                                $script:GroupsNested++
                            }
                            catch {
                                if ($_.Exception.Message -notlike '*already a member*') {
                                    $script:Errors += "Nesting error: '$($row.GroupName)' " +
                                        "into '$parentName': $($_.Exception.Message)"
                                }
                            }
                        }
                    }

                    Write-TestMessage -Message "Group nesting completed" -Type Success
                }
            }

            # Third pass: Assign members based on criteria using batch processing
            if (-not $SkipMemberAssignment -and -not $WhatIfPreference) {
                Write-TestMessage -Message "Preparing group membership assignments..." -Type Info
                $progressParams = @{
                    Activity        = 'Creating Security Groups'
                    Status          = 'Preparing member assignments'
                    PercentComplete = 85
                }
                Write-Progress @progressParams

                # Collect groups that need member assignment
                $groupsForMembership = $groups | Where-Object { [bool]::Parse($_.AutoAssignment) -eq $true }
                $totalMembershipGroups = $groupsForMembership.Count

                if ($totalMembershipGroups -gt 0) {
                    $membershipMessage = 'Processing membership for ' +
                        "$totalMembershipGroups groups..."
                    Write-TestMessage -Message $membershipMessage -Type Info

                    # Process groups in batches
                    $batchCount = [Math]::Ceiling($totalMembershipGroups / $BatchSize)

                    for ($batchIndex = 0; $batchIndex -lt $batchCount; $batchIndex++) {
                        $startIndex = $batchIndex * $BatchSize
                        $endIndex = [Math]::Min(($startIndex + $BatchSize - 1), ($totalMembershipGroups - 1))
                        $currentBatch = $groupsForMembership[$startIndex..$endIndex]

                        $batchProgress = @{
                            Activity        = 'Creating Security Groups'
                            Status          = "Processing membership batch $($batchIndex + 1) of $batchCount"
                            PercentComplete = (85 + (($batchIndex / $batchCount) * 15))
                        }
                        Write-Progress @batchProgress
                        Write-Verbose ("Processing membership batch $($batchIndex + 1)/" +
                            "$batchCount with $($currentBatch.Count) groups")

                        # Wait for job slots to become available
                        while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
                            Start-Sleep -Milliseconds 100

                            # Collect completed jobs
                            $completedJobs = Get-Job -State Completed
                            foreach ($job in $completedJobs) {
                                try {
                                    $jobResult = Receive-Job $job
                                    $script:JobResults.Add($jobResult)
                                    Remove-Job $job
                                }
                                catch {
                                    Write-Warning "Error receiving job result: $($_.Exception.Message)"
                                    $script:Errors += "Job processing error: $($_.Exception.Message)"
                                    Remove-Job $job -Force
                                }
                            }
                        }

                        # Start job for current batch
                        $job = Start-Job -ScriptBlock {
                            # $DomainDN used to be passed in here and never read: the OU
                            # paths are resolved in the parent scope before batching, so the
                            # job only ever needs the rows themselves.
                            # $GroupPrefix is passed in because a job runs in a fresh runspace
                            # and cannot ask the module for the marker. Without it the lookup
                            # below matches the bare CSV name, which is not what the group is
                            # called in the directory, and every membership assignment silently
                            # reports "group not found".
                            param($GroupBatch, $GroupPrefix)

                            # Import Active Directory module in the job
                            Import-Module ActiveDirectory -ErrorAction SilentlyContinue -Verbose:$false

                            $results = @{
                                BatchIndex = $using:batchIndex
                                GroupsProcessed = 0
                                MembersAdded = 0
                                Errors = @()
                            }

                            # The membership switch below sits 44 columns deep, which leaves
                            # no room for a Get-ADUser call written out in full. Splatting
                            # the constant parameters keeps those branches readable and
                            # inside the line limit, without backtick continuations.
                            $eaSilent = @{ ErrorAction = 'SilentlyContinue' }
                            $employeeQuery = @{
                                Filter      = "Enabled -eq 'True'"
                                Properties  = 'EmployeeType'
                                ErrorAction = 'SilentlyContinue'
                            }
                            $managedByQuery = @{
                                Properties  = 'ManagedBy'
                                ErrorAction = 'SilentlyContinue'
                            }
                            $titleDeptQuery = @{
                                Properties  = 'Title', 'Department'
                                ErrorAction = 'SilentlyContinue'
                            }

                            foreach ($group in $GroupBatch) {
                                try {
                                    # Get the AD group
                                    $adFilter = "Name -eq '$($GroupPrefix)$($group.GroupName)'"
                                    $adGroup = Get-ADGroup -Filter $adFilter @eaSilent
                                    if (-not $adGroup) {
                                        $results.Errors += "Group not found: $($group.GroupName)"
                                        continue
                                    }

                                    # Collect members based on group name patterns
                                    $membersToAdd = @()

                                    switch -Regex ($group.GroupName) {
                                        # Employee groups based on employment type
                                        '^All Employees$' {
                                            $allUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $allUsers |
                                                Where-Object { $_.EmployeeType -in @('Full-time', 'Part-time') }
                                        }
                                        '^All Contractors$' {
                                            $contractorUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $contractorUsers |
                                                Where-Object { $_.EmployeeType -eq 'Contractor' }
                                        }
                                        '^All Interns$' {
                                            $internUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $internUsers |
                                                Where-Object { $_.EmployeeType -eq 'Intern' }
                                        }
                                        '^Full Time Employees$' {
                                            $fullTimeUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $fullTimeUsers |
                                                Where-Object { $_.EmployeeType -eq 'Full-time' }
                                        }
                                        '^Contract Workers$' {
                                            $contractUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $contractUsers |
                                                Where-Object { $_.EmployeeType -eq 'Contractor' }
                                        }
                                        '^Intern Employees$' {
                                            $internUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $internUsers |
                                                Where-Object { $_.EmployeeType -eq 'Intern' }
                                        }

                                        # Department-based groups
                                        '^(Executives|Executive.*)$' {
                                            $adFilter = "Department -eq 'Executive'"
                                            $execUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $execUsers
                                        }
                                        '^(Operations|Operation.*)$' {
                                            $adFilter = "Department -eq 'Operations'"
                                            $opsUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $opsUsers
                                        }
                                        '^(Engineering|Engineering.*)$' {
                                            $adFilter =
                                                "Department -eq 'Engineering' -or " +
                                                "Department -eq 'Engineering Operations'"
                                            $engUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $engUsers
                                        }
                                        '^(Sales|Sales.*)$' {
                                            $adFilter =
                                                "Department -eq 'Sales' -or " +
                                                "Department -eq 'Sales Engagement Management'"
                                            $salesUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $salesUsers
                                        }
                                        '^(Marketing|Marketing.*)$' {
                                            $adFilter = "Department -eq 'Marketing'"
                                            $marketingUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $marketingUsers
                                        }
                                        '^(Accounting|Finance)$' {
                                            $adFilter = "Department -eq 'Accounting' -or Department -eq 'Finance'"
                                            $financeUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $financeUsers
                                        }
                                        '^Human Resources$' {
                                            $adFilter = "Department -eq 'Human Resources'"
                                            $hrUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $hrUsers
                                        }
                                        '^Project Management$' {
                                            $adFilter = "Department -eq 'Project Management'"
                                            $pmUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $pmUsers
                                        }
                                        '^Strategy Consulting$' {
                                            $adFilter = "Department -eq 'Strategy Consulting'"
                                            $stratUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $stratUsers
                                        }
                                        '^Content Management$' {
                                            $adFilter = "Department -eq 'Content Management Consulting'"
                                            $contentUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $contentUsers
                                        }
                                        '^CRM Strategy$' {
                                            $adFilter = "Department -eq 'CRM Strategy'"
                                            $crmUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $crmUsers
                                        }
                                        '^Senior Management$' {
                                            $adFilter = "Department -eq 'Senior Management'"
                                            $seniorMgmt = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $seniorMgmt
                                        }
                                        '^Creative$' {
                                            $adFilter = "Department -eq 'Creative'"
                                            $creativeUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $creativeUsers
                                        }
                                        '^CVP of IT$' {
                                            $adFilter = "Department -eq 'CVP of IT'"
                                            $cvpITUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $cvpITUsers
                                        }

                                        # Management level groups
                                        '^Directors$' {
                                            $adFilter = "Title -like '*Director*'"
                                            $directors = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $directors
                                        }
                                        '^Managers$' {
                                            $adFilter = "Title -like '*Manager*'"
                                            $managers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $managers
                                        }
                                        '^VPs and Above$' {
                                            $adFilter =
                                                "Title -like '*VP*' -or Title -like '*SVP*' -or " +
                                                "Title -like '*CVP*' -or Title -like '*CEO*' -or " +
                                                "Title -like '*COO*' -or Title -like '*CFO*' -or " +
                                                "Title -like '*CTO*' -or Title -like '*President*'"
                                            $vps = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $vps
                                        }
                                        '^C-Level$' {
                                            $adFilter =
                                                "Title -like '*CEO*' -or Title -like '*COO*' -or " +
                                                "Title -like '*CFO*' -or Title -like '*CTO*'"
                                            $clevel = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $clevel
                                        }
                                        '^Sales Management$' {
                                            $adFilter =
                                                "(Department -eq 'Sales' -or " +
                                                "Department -eq 'Sales Engagement Management') -and " +
                                                "(Title -like '*Manager*' -or Title -like '*Director*' -or " +
                                                "Title -like '*VP*')"
                                            $salesMgmt = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $salesMgmt
                                        }
                                        '^Sales Engagement Management$' {
                                            $adFilter = "Department -eq 'Sales Engagement Management'"
                                            $salesEngagement = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $salesEngagement
                                        }

                                        # Location-based groups - handle all office patterns
                                        'Office$|^Seattle.*Office$' {
                                            if ($group.GroupName -eq 'Seattle Main Office') {
                                                $adFilter = "Office -eq 'Seattle - Main'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Seattle Engineering Office') {
                                                $adFilter = "Office -eq 'Seattle - Engineering'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Seattle Finance Office') {
                                                $adFilter = "Office -eq 'Seattle - Finance'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Atlanta Office') {
                                                $adFilter = "Office -eq 'Atlanta - Southeast'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Boston Office') {
                                                $adFilter = "Office -eq 'Boston - Northeast'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Chicago Office') {
                                                $adFilter = "Office -eq 'Chicago - Central'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Houston Office') {
                                                $adFilter = "Office -eq 'Houston - Sales'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'London Office') {
                                                $adFilter = "Office -eq 'London - International'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Los Angeles Office') {
                                                $adFilter = "Office -eq 'Los Angeles - West'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'New York Office') {
                                                $adFilter = "Office -like '*New York*'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            elseif ($group.GroupName -eq 'Richmond Office') {
                                                $adFilter = "Office -eq 'Richmond - East'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            else {
                                                $locationName = ($group.GroupName -replace ' Office$', '')
                                                $adFilter = "Office -like '*$locationName*'"
                                                $locationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            }
                                            $membersToAdd += $locationUsers
                                        }
                                        '^Remote Workers$' {
                                            $adFilter = "Office -like '*Remote*'"
                                            $remoteUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $remoteUsers
                                        }

                                        # Technology access groups
                                        '^VPN Users$' {
                                            $adFilter =
                                                "Office -like '*Remote*' -or Department -eq 'Sales' -or " +
                                                "Department -eq 'Sales Engagement Management'"
                                            $vpnUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $vpnUsers
                                        }
                                        '^WiFi Users$' {
                                            $adFilter = "Enabled -eq 'True'"
                                            $wifiUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $wifiUsers
                                        }
                                        '^Remote Desktop Users$' {
                                            $adFilter =
                                                "Office -like '*Remote*' -or Department -eq 'Operations' -or " +
                                                "Title -like '*IT*'"
                                            $rdpUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $rdpUsers
                                        }

                                        # Device-based groups
                                        '^Workstation Users$' {
                                            $adFilter = "Enabled -eq 'True'"
                                            $workstationUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $workstationUsers |
                                                Where-Object {
                                                    $_.Office -notlike '*Remote*' -and
                                                    $_.Department -notin @('Sales', 'Sales Engagement Management')
                                                }
                                        }

                                        # Application access groups - basic access for all employees
                                        ('^Email Users$|^Calendar Users$|^Internet Access Basic$|' +
                                            '^Conference Room Booking$|^File Share Users$') {
                                            $adFilter = "Enabled -eq 'True'"
                                            $basicUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $basicUsers
                                        }
                                        '^Internet Access Full$' {
                                            $fullAccessUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $fullAccessUsers |
                                                Where-Object { $_.EmployeeType -ne 'Intern' }
                                        }
                                        '^Expense System Access$' {
                                            $expenseUsers = Get-ADUser @employeeQuery
                                            $membersToAdd += $expenseUsers |
                                                Where-Object { $_.EmployeeType -ne 'Intern' }
                                        }

                                        # Department computing groups
                                        '^Engineering Computing$' {
                                            $adFilter =
                                                "Department -eq 'Engineering' -or " +
                                                "Department -eq 'Engineering Operations'"
                                            $engComputing = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $engComputing
                                        }
                                        '^Executive Computing$' {
                                            $adFilter = "Department -eq 'Executive'"
                                            $execComputing = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $execComputing
                                        }
                                        '^Sales Computing$' {
                                            $adFilter =
                                                "Department -eq 'Sales' -or " +
                                                "Department -eq 'Sales Engagement Management'"
                                            $salesComputing = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $salesComputing
                                        }

                                        # Specific access groups based on department and role
                                        '^Development Tools$|^Engineering File Access$' {
                                            $adFilter =
                                                "Department -eq 'Engineering' -or " +
                                                "Department -eq 'Engineering Operations'"
                                            $devUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $devUsers
                                        }
                                        '^Design Tools$' {
                                            $adFilter = "Department -eq 'Marketing' -or Department -eq 'Creative'"
                                            $designUsers = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $designUsers
                                        }
                                        '^Executive File Access$|^Executive Floor Access$' {
                                            $adFilter =
                                                "Department -eq 'Executive' -or " +
                                                "Department -eq 'Senior Management'"
                                            $execAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $execAccess
                                        }
                                        '^Finance File Access$|^Financial Applications$|^Payroll System Access$' {
                                            $adFilter =
                                                "Department -eq 'Accounting' -or " +
                                                "Department -eq 'Human Resources'"
                                            $financeAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $financeAccess
                                        }
                                        '^HR Applications$|^HR File Access$' {
                                            $adFilter = "Department -eq 'Human Resources'"
                                            $hrAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $hrAccess
                                        }
                                        '^Project File Access$|^Project Management Tools$' {
                                            $adFilter = "Department -eq 'Project Management'"
                                            $projectAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $projectAccess
                                        }
                                        '^CRM System Access$' {
                                            $adFilter =
                                                "Department -eq 'Sales' -or " +
                                                "Department -eq 'Sales Engagement Management' -or " +
                                                "Department -eq 'Marketing' -or Department -eq 'CRM Strategy'"
                                            $crmAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $crmAccess
                                        }
                                        '^Database Access Read$|^Business Intelligence$' {
                                            $adFilter =
                                                "Title -like '*Analyst*' -or Title -like '*Manager*' -or " +
                                                "Title -like '*Director*'"
                                            $dbRead = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $dbRead
                                        }
                                        '^Database Access Write$' {
                                            $adFilter =
                                                "(Department -eq 'Engineering' -or " +
                                                "Department -eq 'Engineering Operations') -and " +
                                                "(Title -like '*Engineer*' -or Title -like '*Developer*')"
                                            $dbWrite = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $dbWrite
                                        }
                                        '^Color Printer Access$' {
                                            $adFilter =
                                                "Department -eq 'Marketing' -or Department -eq 'Executive' -or " +
                                                "Department -eq 'Senior Management'"
                                            $colorPrint = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $colorPrint
                                        }

                                        # Printer access by location
                                        '^Printer Access Engineering$' {
                                            $adFilter = "Office -eq 'Seattle - Engineering'"
                                            $printEng = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $printEng
                                        }
                                        '^Printer Access Finance$' {
                                            $adFilter = "Office -eq 'Seattle - Finance'"
                                            $printFin = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $printFin
                                        }
                                        '^Printer Access Main$' {
                                            $adFilter = "Office -eq 'Seattle - Main'"
                                            $printMain = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $printMain
                                        }

                                        # Administrative groups
                                        '^After Hours Access$' {
                                            $adFilter =
                                                "Department -eq 'Operations' -and (Title -like '*IT*' -or " +
                                                "Title -like '*Manager*')"
                                            $afterHoursAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $afterHoursAccess
                                        }
                                        '^Backup System Access$' {
                                            $adFilter =
                                                "Department -eq 'Operations' -and (Title -like '*IT*' -or " +
                                                "Title -like '*Administrator*')"
                                            $backupAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $backupAccess
                                        }
                                        '^Monitoring System Access$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $monitoringAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $monitoringAccess
                                        }
                                        '^Security Event Review$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $securityAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $securityAccess
                                        }
                                        '^Server Room Access$' {
                                            $adFilter =
                                                "Department -eq 'Operations' -and (Title -like '*IT*' -or " +
                                                "Title -like '*Manager*')"
                                            $serverRoomAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $serverRoomAccess
                                        }
                                        '^Software Installation$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $softwareInstall = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $softwareInstall
                                        }
                                        '^Payroll System Access$' {
                                            $adFilter =
                                                "Department -eq 'Human Resources' -or " +
                                                "(Department -eq 'Accounting' -and Title -like '*Manager*')"
                                            $payrollAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $payrollAccess
                                        }
                                        '^Database Access Write$' {
                                            $adFilter =
                                                "(Department -eq 'Engineering' -or " +
                                                "Department -eq 'Engineering Operations') -and " +
                                                "(Title -like '*Engineer*' -or Title -like '*Developer*')"
                                            $dbWrite = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $dbWrite
                                        }
                                        '^Compliance Reporting$' {
                                            $adFilter =
                                                "Department -eq 'Accounting' -or " +
                                                "Department -eq 'Human Resources'"
                                            $complianceAccess = Get-ADUser -Filter $adFilter @eaSilent
                                            $membersToAdd += $complianceAccess
                                        }
                                        # Mobile device and laptop users based on device assignments
                                        '^Mobile Device Users$' {
                                            # Get all mobile devices and find their owners via ManagedBy property
                                            $adFilter = "Name -like '*Mobile*'"
                                            $mobileDevices = Get-ADComputer -Filter $adFilter @managedByQuery
                                            $mobileUserDNs = $mobileDevices |
                                                Where-Object { $_.ManagedBy } |
                                                Select-Object -ExpandProperty ManagedBy -Unique
                                            $membersToAdd += $mobileUserDNs |
                                                ForEach-Object { Get-ADUser -Identity $_ @eaSilent } |
                                                Where-Object { $_ }
                                        }
                                        '^Laptop Users$' {
                                            # Get all laptop devices and find their owners via ManagedBy property
                                            $adFilter = "Name -like '*Laptop*'"
                                            $laptopDevices = Get-ADComputer -Filter $adFilter @managedByQuery
                                            $laptopUserDNs = $laptopDevices |
                                                Where-Object { $_.ManagedBy } |
                                                Select-Object -ExpandProperty ManagedBy -Unique
                                            $membersToAdd += $laptopUserDNs |
                                                ForEach-Object { Get-ADUser -Identity $_ @eaSilent } |
                                                Where-Object { $_ }
                                        }
                                        # Test administrative groups - assign to IT staff for testing
                                        '^Test Domain Admins$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $testDomainAdmins = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testDomainAdmins | Select-Object -First 3
                                        }
                                        '^Test Enterprise Admins$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $testEnterpriseAdmins = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testEnterpriseAdmins | Select-Object -First 2
                                        }
                                        '^Test Schema Admins$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $testSchemaAdmins = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testSchemaAdmins | Select-Object -First 1
                                        }
                                        '^Test Backup Operators$' {
                                            $adFilter = "Department -eq 'Operations' -and " +
                                                "(Title -like '*IT*' -or Title -like '*Technician*')"
                                            $testBackupOps = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testBackupOps | Select-Object -First 4
                                        }
                                        '^Test Server Operators$' {
                                            $adFilter = "Department -eq 'Operations' -and " +
                                                "(Title -like '*IT*' -or Title -like '*Administrator*')"
                                            $testServerOps = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testServerOps | Select-Object -First 5
                                        }
                                        '^Test Account Operators$' {
                                            $adFilter = "Department -eq 'Operations' -and Title -like '*IT*'"
                                            $testAccountOps = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testAccountOps | Select-Object -First 3
                                        }
                                        '^Test Print Operators$' {
                                            $adFilter = "Department -eq 'Operations' -and " +
                                                "(Title -like '*IT*' -or Title -like '*Support*')"
                                            $testPrintOps = Get-ADUser -Filter $adFilter @titleDeptQuery
                                            $membersToAdd += $testPrintOps | Select-Object -First 2
                                        }

                                        default {
                                            # No specific membership logic - group will remain empty
                                            # This is intentional for groups that require manual assignment
                                        }
                                    }

                                    # Add members to group using batch Add-ADGroupMember
                                    $candidateMember = @($membersToAdd)

                                    if ($candidateMember.Count -gt 0) {
                                        try {
                                            # Use batch member addition for efficiency.
                                            #
                                            # @() around the filter is load-bearing. Where-Object
                                            # returns a bare ADUser when exactly one member
                                            # matches, and ADUser surfaces AD attributes through a
                                            # dictionary accessor - so .Count does not mean "one",
                                            # it looks up an attribute named Count, finds none, and
                                            # hands back an empty ADPropertyValueCollection.
                                            #
                                            # That poisoned all three lines below: the -gt 0 guard
                                            # was never true so the batch add was skipped outright,
                                            # += threw op_Addition, and the subtraction threw
                                            # op_Subtraction into the catch - which then reported
                                            # "Batch add failed" for a batch that had never run and
                                            # fell through to the one-at-a-time path. Members did
                                            # land, by the slow route, behind a misleading error.
                                            $validMembers = @($membersToAdd |
                                                Where-Object { $_ -and $_.DistinguishedName })

                                            if ($validMembers.Count -gt 0) {
                                                $memberDNs = $validMembers |
                                                    ForEach-Object { $_.DistinguishedName }
                                                $addBatch = @{
                                                    Identity    = $adGroup.DistinguishedName
                                                    Members     = $memberDNs
                                                    ErrorAction = 'Stop'
                                                }
                                                Add-ADGroupMember @addBatch
                                                $results.MembersAdded += $validMembers.Count
                                            }
                                            if ($candidateMember.Count -ne $validMembers.Count) {
                                                $invalidCount = $candidateMember.Count - $validMembers.Count
                                                $results.Errors += "Skipped $invalidCount null or " +
                                                    "invalid members for group $($group.GroupName)"
                                            }
                                        }
                                        catch {
                                            # If batch fails, try individual additions
                                            $batchError = $_.Exception.Message
                                            $results.Errors += "Batch add failed for $($group.GroupName), " +
                                                "trying individual adds: $batchError"

                                            foreach ($member in $candidateMember) {
                                                try {
                                                    if ($member -and $member.DistinguishedName) {
                                                        $addOne = @{
                                                            Identity    = $adGroup.DistinguishedName
                                                            Members     = $member.DistinguishedName
                                                            ErrorAction = 'Stop'
                                                        }
                                                        Add-ADGroupMember @addOne
                                                        $results.MembersAdded++
                                                    }
                                                    else {
                                                        $results.Errors += 'Skipped null or invalid ' +
                                                            "member for group $($group.GroupName)"
                                                    }
                                                }
                                                catch {
                                                    if ($_.Exception.Message -notlike "*already a member*") {
                                                        $memberName = if ($member -and $member.Name) {
                                                            $member.Name
                                                        }
                                                        else {
                                                            'Unknown Member'
                                                        }
                                                        $results.Errors += "Failed to add $memberName " +
                                                            "to $($group.GroupName): $($_.Exception.Message)"
                                                    }
                                                    # If already a member, just count it as added (no error)
                                                    elseif ($_.Exception.Message -like "*already a member*") {
                                                        $results.MembersAdded++
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    $results.GroupsProcessed++
                                }
                                catch {
                                    $results.Errors += "Error processing group $($group.GroupName): " +
                                        "$($_.Exception.Message)"
                                }
                            }

                            return $results
                        } -ArgumentList $currentBatch, (Get-ADTestSeedMarker).Prefix

                        $script:MembershipJobs.Add($job)
                    }

                    # Wait for all jobs to complete and collect results
                    $waitMessage = 'Waiting for membership assignment jobs to complete...'
                    Write-TestMessage -Message $waitMessage -Type Info

                    do {
                        Start-Sleep -Milliseconds 500
                        $runningJobs = Get-Job -State Running

                        # Collect completed jobs
                        $completedJobs = Get-Job -State Completed
                        foreach ($job in $completedJobs) {
                            try {
                                $jobResult = Receive-Job $job
                                $script:JobResults.Add($jobResult)
                                Remove-Job $job
                            }
                            catch {
                                Write-Warning "Error receiving job result: $($_.Exception.Message)"
                                $script:Errors += "Job processing error: $($_.Exception.Message)"
                                Remove-Job $job -Force
                            }
                        }

                        $remainingJobs = (Get-Job -State Running).Count
                        if ($remainingJobs -gt 0) {
                            $waitProgress = @{
                                Activity        = 'Creating Security Groups'
                                Status          = "Waiting for $remainingJobs membership jobs to complete"
                                PercentComplete = 95
                            }
                            Write-Progress @waitProgress
                        }

                    } while ($runningJobs.Count -gt 0)

                    # Process any failed jobs
                    $failedJobs = Get-Job -State Failed
                    foreach ($job in $failedJobs) {
                        $script:Errors += "Job failed: $($job.Name)"
                        Remove-Job $job -Force
                    }

                    # Aggregate results
                    foreach ($result in $script:JobResults) {
                        $script:MembersAdded += $result.MembersAdded
                        if ($result.Errors -and $result.Errors.Count -gt 0) {
                            # $jobError, not $error. $error is the automatic variable holding
                            # the session's error history; assigning to it in a loop discards
                            # that history for the rest of the scope and PSScriptAnalyzer
                            # rejects it outright.
                            foreach ($jobError in $result.Errors) {
                                if (-not [string]::IsNullOrWhiteSpace($jobError)) {
                                    $script:Errors += $jobError
                                }
                            }
                        }
                    }

                    Write-TestMessage -Message "Membership assignment completed" -Type Success
                }
            }

            Write-Progress -Activity "Creating Security Groups" -Status "Complete" -PercentComplete 100 -Completed

            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalGroups = $totalGroups
                CreatedGroups = $script:GroupsCreated
                SkippedGroups = $script:GroupsSkipped
                MembersAdded = if ($SkipMemberAssignment) { 0 } else { $script:MembersAdded }
                GroupsNested = if ($SkipMemberAssignment) { 0 } else { $script:GroupsNested }
                Errors = $script:Errors
            }

            # Display summary
            Write-TestMessage -Message "Security Group Creation Summary" -Type Success
            Write-Host "  Groups Created: $($results.CreatedGroups)" -ForegroundColor Green
            Write-Host "  Groups Skipped: $($results.SkippedGroups)" -ForegroundColor Yellow
            if (-not $SkipMemberAssignment) {
                Write-Host "  Members Added: $($results.MembersAdded)" -ForegroundColor Green
                Write-Host "  Groups Nested: $($results.GroupsNested)" -ForegroundColor Green
            }

            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            Write-Error "Failed to create security groups: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestSecurityGroups - CorrelationId: $correlationId"
    }
}
