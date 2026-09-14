function New-ADTestSecurityGroups {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates Active Directory test security groups from CSV data
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Exported name; renaming it would break callers.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$SkipMemberAssignment,

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

        # Every lookup by name in this step is scoped here. A seeded group is found, nested
        # and owned only within the seed's own tree, so an object elsewhere in the domain that
        # shares a name is never read as ours.
        $seedRoot = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
        $seedPrefix = (Get-ADTestSeedMarker).Prefix

        # Counters
        $script:GroupsCreated = 0
        $script:GroupsSkipped = 0
        $script:MembersAdded = 0
        $script:GroupsNested = 0
        $script:Errors = @()

        # Job tracking for batch processing
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
                    $existingGroup = Get-ADGroup -Filter $groupFilter -SearchBase $seedRoot -ErrorAction SilentlyContinue
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
                    # sibling CSVs write owners that way. The search is scoped to the seed
                    # OU, so a real account of the same name is never made a seeded group's
                    # owner.
                    if ($group.ManagedBy) {
                        $ownerName = $group.ManagedBy -replace '^CN=', ''
                        $ownerFilter = "Name -eq '$($ownerName.Replace("'", "''"))'"
                        $owner = Get-ADUser -Filter $ownerFilter -SearchBase $seedRoot -ErrorAction SilentlyContinue

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
                        $child = Get-ADGroup -Filter $childFilter -SearchBase $seedRoot -ErrorAction SilentlyContinue

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
                            $parent = Get-ADGroup -Filter $parentFilter -SearchBase $seedRoot -ErrorAction SilentlyContinue

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

            # Third pass: membership, one rule per row, resolved inside the seed OU.
            #
            # The rules live in the CSV (MemberFilter, MemberSource, MemberLimit) and are read by
            # Resolve-ADTestGroupMember, so adding a group is a data change and the rules can be
            # unit-tested. They used to be a regex switch on group names inside a background
            # job, searching the whole domain, which is how twelve real accounts came to be in
            # seeded groups and how a group matching two rules counted its members twice.
            if (-not $SkipMemberAssignment -and -not $WhatIfPreference) {
                $groupsForMembership = @($groups | Where-Object { [bool]::Parse($_.AutoAssignment) -eq $true })

                if ($groupsForMembership.Count -gt 0) {
                    Write-TestMessage -Message "Processing membership for $($groupsForMembership.Count) groups..." -Type Info
                    $index = 0

                    foreach ($group in $groupsForMembership) {
                        $index++
                        Write-Progress -Activity 'Creating Security Groups' -Status "Membership: $($group.GroupName)" `
                            -PercentComplete (85 + (($index / $groupsForMembership.Count) * 15))

                        try {
                            $adGroup = Get-ADGroup -Filter "Name -eq '$($seedPrefix)$($group.GroupName.Replace("'", "''"))'" `
                                -SearchBase $seedRoot -ErrorAction SilentlyContinue
                            if (-not $adGroup) {
                                $script:Errors += "Group not found: $($group.GroupName)"
                                continue
                            }

                            $members = @(Resolve-ADTestGroupMember -Rule $group -SeedRoot $seedRoot)
                            if ($members.Count -eq 0) { continue }

                            try {
                                Add-ADGroupMember -Identity $adGroup.DistinguishedName -Members @($members.DistinguishedName) -ErrorAction Stop
                                $script:MembersAdded += $members.Count
                            }
                            catch {
                                # One refused member fails the whole batch, so fall back to one at a
                                # time. A member the group already holds is neither an error nor an
                                # addition.
                                Write-Verbose "Batch add to $($group.GroupName) failed ($($_.Exception.Message)); adding one at a time"
                                foreach ($member in $members) {
                                    try {
                                        Add-ADGroupMember -Identity $adGroup.DistinguishedName -Members $member.DistinguishedName -ErrorAction Stop
                                        $script:MembersAdded++
                                    }
                                    catch {
                                        if ($_.Exception.Message -notlike '*already a member*') {
                                            $script:Errors += "Failed to add $($member.SamAccountName) to $($group.GroupName): $($_.Exception.Message)"
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            $script:Errors += "Membership error for $($group.GroupName): $($_.Exception.Message)"
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
