function New-ADTestUser {
    <#
    .SYNOPSIS
        Creates Active Directory test user accounts from CSV data
    .DESCRIPTION
        Creates user accounts in Active Directory based on data from ADUsers.csv.
        Users are placed in appropriate department OUs and configured with
        photos, manager relationships, and other attributes.

    .PARAMETER WhatIf
        Shows what would be created without making changes

    .PARAMETER IncludePhotos
        Include user photos from Data/UserImages folder

    .PARAMETER BatchSize
        Number of users to process in each batch. Default is 15.
        Larger batches improve performance but may consume more resources.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent batch operations. Default is 4.
        Adjust based on your domain controller's capacity.

    .PARAMETER PassThru
        Returns a PSCustomObject with creation results and statistics

    .EXAMPLE
        New-ADTestUser
        Creates all users from ADUsers.csv

    .EXAMPLE
        New-ADTestUser -BatchSize 20 -ThrottleLimit 3
        Creates users in batches of 20 with maximum 3 concurrent batches

    .EXAMPLE
        New-ADTestUser -WhatIf
        Shows what users would be created

    .EXAMPLE
        $results = New-ADTestUser -PassThru -BatchSize 10
        Creates users in batches of 10 and returns results object

    .OUTPUTS
        PSCustomObject with creation results and statistics (when -PassThru is used)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-02

        REQUIREMENTS:
        - OU structure must exist (run New-ADTestOUStructure first)
        - ADUsers.csv must be present in Data folder
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = 'Job blocks take param() and bind by -ArgumentList; Using: does not apply.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Passed into the job and read by the preference system, not by name.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'AccountPassword arrives as a SecureString through -ArgumentList.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$IncludePhotos,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$BatchSize = 15,

        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$ThrottleLimit = 4,

        # Password every generated user is created with.
        #
        # A parameter rather than a literal buried in the job script block below, so a
        # caller who wants something other than the documented default can say so without
        # editing the module. The default is deliberately a known, weak, shared value: these
        # are lab accounts and being able to sign in as one is usually the point. Anything
        # random would have to be recorded somewhere to be usable, and this module already
        # has a vault for the accounts where that matters - the service accounts.
        [Parameter()]
        [ValidateNotNull()]
        [System.Security.SecureString]$AccountPassword = (ConvertTo-TestSecureString -PlainText 'Password123!'),

        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestUser - CorrelationId: $correlationId"

        # Get data paths
        $dataPath = Get-ADTestDataPath
        $usersCSV = Join-Path $dataPath "ADUsers.csv"
        $imageFolder = Join-Path $dataPath "UserImages"

        # Verify prerequisites
        if (-not (Test-Path $usersCSV)) {
            throw "ADUsers.csv not found at: $usersCSV"
        }

        # Get domain information
        $domain = Get-ADTestDomain

        # Resolved once here: a job runs in a fresh runspace and cannot call back into the
        # module to ask for the marker.
        $seedMarker = Get-ADTestSeedMarker

        # Counters
        $script:UsersCreated = 0
        $script:UsersSkipped = 0
        $script:PhotosAdded = 0
        $script:ManagersSet = 0
        $script:Errors = @()
        $script:ProcessingJobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()

        Write-Verbose "Batch processing configuration: BatchSize=$BatchSize, ThrottleLimit=$ThrottleLimit"
    }

    process {
        try {
            Write-TestMessage -Message "Creating Active Directory Test Users" -Type Header
            Write-TestMessage -Message "Loading user data from CSV..." -Type Info

            # Import user data
            $users = Import-Csv $usersCSV
            Write-Verbose "Loaded $($users.Count) users from CSV"

            # Sort users to create managers before their reports (simplified approach)
            $sortedUsers = $users | Sort-Object {
                if ([string]::IsNullOrWhiteSpace($_.Manager)) { 0 } else { 1 }
            }

            $totalUsers = $sortedUsers.Count
            Write-TestMessage -Message "Processing $totalUsers users in batches of $BatchSize..." -Type Info

            # Group users into batches
            $userBatches = @()
            for ($i = 0; $i -lt $totalUsers; $i += $BatchSize) {
                $batchEnd = [Math]::Min($i + $BatchSize - 1, $totalUsers - 1)
                $userBatches += ,@($sortedUsers[$i..$batchEnd])
            }

            Write-Verbose "Created $($userBatches.Count) batches for processing"

            # Process batches with throttling
            $batchNumber = 0
            $completedBatches = 0

            foreach ($batch in $userBatches) {
                $batchNumber++

                # Wait for available slot if at throttle limit
                while ($script:ProcessingJobs.Count -ge $ThrottleLimit) {
                    Start-Sleep -Milliseconds 500

                    # Check for completed jobs
                    $completedJobs = $script:ProcessingJobs | Where-Object { $_.State -eq 'Completed' }
                    if ($completedJobs) {
                        foreach ($job in $completedJobs) {
                            $result = Receive-Job -Job $job
                            Remove-Job -Job $job

                            # Aggregate results
                            $script:UsersCreated += $result.Created
                            $script:UsersSkipped += $result.Skipped
                            $script:PhotosAdded += $result.PhotosAdded
                            $script:Errors += $result.Errors

                            $completedBatches++
                        }

                        # Remove completed jobs from tracking
                        $remainingJobs = $script:ProcessingJobs | Where-Object { $_.State -ne 'Completed' }
                        $script:ProcessingJobs.Clear()
                        foreach ($job in $remainingJobs) {
                            $script:ProcessingJobs.Add($job)
                        }

                        # Update progress
                        # Reserve the last 20% for manager relationships
                        $percentComplete = ($completedBatches / $userBatches.Count) * 80
                        Write-Progress -Activity "Creating User Batches" -Status ("Completed $completedBatches " +
                            "of $($userBatches.Count) batches") -PercentComplete $percentComplete
                    }
                }

                # Start new batch job
                $jobName = "UserBatch_$batchNumber"
                Write-Verbose "Starting batch $batchNumber with $($batch.Count) users"

                $job = Start-Job -Name $jobName -ScriptBlock {
                    # $RootName is passed in because a job runs in a fresh runspace: module
                    # scope does not travel, so $script:ADTestRootName is empty inside here and
                    # every OU path built from it would be 'OU=Users,OU=,DC=...'.
                    param($BatchRecord, $Domain, $IncludePhotos, $imageFolder,
                        $WhatIfPreference, $VerbosePreference, $AccountPassword, $RootName, $SeedTag)

                    # Import required modules in job
                    Import-Module ActiveDirectory -Verbose:$false

                    $batchResults = @{
                        Created = 0
                        Skipped = 0
                        PhotosAdded = 0
                        Errors = @()
                    }

                    foreach ($user in $BatchRecord) {
                        try {
                            # Debug: Check if required objects are available
                            if (-not $Domain) {
                                throw "Domain parameter is null"
                            }
                            if (-not $Domain.DomainDN) {
                                throw "Domain.DomainDN is null"
                            }
                            if (-not $user) {
                                throw "User object is null"
                            }

                            # Skip if user already exists
                            $existingUser = Get-ADUser -Filter ("SamAccountName -eq " +
                                "'$($user.SamAccountName)'") -ErrorAction SilentlyContinue
                            if ($existingUser) {
                                Write-Verbose "User $($user.SamAccountName) already exists, skipping"
                                $batchResults.Skipped++
                                continue
                            }

                            # Determine OU path
                            $ouPath = "OU=$($user.Department),OU=Users,OU=$RootName,$($Domain.DomainDN)"

                            # Verify OU exists
                            try {
                                Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                            }
                            catch {
                                Write-Verbose "OU not found: $ouPath. Using default Users container."
                                $ouPath = "CN=Users,$($Domain.DomainDN)"
                            }

                            # Generate domain-dependent fields dynamically
                            $dynamicEmail = if ([string]::IsNullOrWhiteSpace($user.mail)) {
                                "$($user.SamAccountName)@$($Domain.DNSName)"
                            } else {
                                "$($user.mail)@$($Domain.DNSName)"
                            }

                            $dynamicUPN = if ([string]::IsNullOrWhiteSpace($user.UserPrincipalName)) {
                                $dynamicEmail
                            } else {
                                "$($user.UserPrincipalName)@$($Domain.DNSName)"
                            }

                            # Prepare user parameters
                            $userParams = @{
                                Name = $user.Name
                                SamAccountName = $user.SamAccountName
                                UserPrincipalName = $dynamicUPN
                                GivenName = $user.GivenName
                                Surname = $user.Surname
                                DisplayName = $user.Name
                                EmailAddress = $dynamicEmail
                                Title = $user.Title
                                Department = $user.Department
                                OfficePhone = $user.OfficePhone
                                MobilePhone = $user.MobilePhone
                                Office = $user.Office
                                StreetAddress = $user.StreetAddress
                                City = $user.City
                                State = $user.State
                                PostalCode = $user.PostalCode
                                Description = $user.Description
                                EmployeeID = $user.EmployeeID
                                # adminDescription carries the seed tag. The seeded people are the
                                # one thing this module does not prefix, so this attribute is what
                                # proves the account is ours once it is out of its container.
                                OtherAttributes = @{ EmployeeType = $user.EmployeeType; adminDescription = $SeedTag }
                                Path = $ouPath
                                Enabled = if ([string]::IsNullOrWhiteSpace($user.Enabled)) {
                                    $true
                                }
                                else {
                                    [bool]::Parse($user.Enabled)
                                }
                                PasswordNeverExpires = $true
                                CannotChangePassword = $false
                                # Built by the caller and passed in. A SecureString survives
                                # Start-Job -ArgumentList intact - verified, not assumed -
                                # so the value never has to exist as plain text in here.
                                AccountPassword = $AccountPassword
                            }

                            # Create user
                            if (-not $WhatIfPreference) {
                                Write-Verbose "Creating user: $($user.Name) in $ouPath"
                                New-ADUser @userParams
                                $batchResults.Created++

                                # Add photo if requested and available
                                if ($IncludePhotos) {
                                    $photoPath = Join-Path $imageFolder "$($user.Name).jpg"
                                    if (Test-Path $photoPath) {
                                        try {
                                            $photo = [System.IO.File]::ReadAllBytes($photoPath)
                                            Set-ADUser -Identity $user.SamAccountName -Replace @{
                                                thumbnailPhoto = $photo
                                            }
                                            Write-Verbose "Added photo for $($user.Name)"
                                            $batchResults.PhotosAdded++
                                        }
                                        catch {
                                            $batchResults.Errors += ("Photo error for $($user.Name): " +
                                                "$($_.Exception.Message)")
                                        }
                                    }
                                }
                            }
                            else {
                                Write-Verbose "Would create user: $($user.Name) in $ouPath"
                                $batchResults.Created++
                            }
                        }
                        catch {
                            $batchResults.Errors += ("User creation error for $($user.Name): " +
                                "$($_.Exception.Message)")
                        }
                    }

                    return $batchResults
                } -ArgumentList $batch, $domain, $IncludePhotos, $imageFolder,
                    $WhatIfPreference, $VerbosePreference, $AccountPassword,
                    $script:ADTestRootName, $seedMarker.Tag

                $script:ProcessingJobs.Add($job)
            }

            # Wait for all remaining jobs to complete
            Write-Verbose "Waiting for all batch jobs to complete..."
            while ($script:ProcessingJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 500

                $completedJobs = $script:ProcessingJobs | Where-Object { $_.State -eq 'Completed' }
                if ($completedJobs) {
                    foreach ($job in $completedJobs) {
                        $result = Receive-Job -Job $job
                        Remove-Job -Job $job

                        # Aggregate results
                        $script:UsersCreated += $result.Created
                        $script:UsersSkipped += $result.Skipped
                        $script:PhotosAdded += $result.PhotosAdded
                        $script:Errors += $result.Errors

                        $completedBatches++
                    }

                    # Remove completed jobs from tracking
                    $remainingJobs = $script:ProcessingJobs | Where-Object { $_.State -ne 'Completed' }
                    $script:ProcessingJobs.Clear()
                    foreach ($job in $remainingJobs) {
                        $script:ProcessingJobs.Add($job)
                    }

                    # Update progress
                    $percentComplete = ($completedBatches / $userBatches.Count) * 80
                    Write-Progress -Activity "Creating User Batches" -Status ("Completed $completedBatches of " +
                        "$($userBatches.Count) batches") -PercentComplete $percentComplete
                }
            }

            # Second pass: Set manager relationships using batch processing
            if (-not $WhatIfPreference) {
                Write-TestMessage -Message "Setting manager relationships..." -Type Info
                Write-Progress -Activity "Creating Users" -Status ("Setting manager " +
                    "relationships") -PercentComplete 85

                # Filter users that need manager assignments
                $usersWithManagers = $sortedUsers | Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_.Manager) -and $_.Manager -ne "CN="
                }

                if ($usersWithManagers.Count -gt 0) {
                    Write-Verbose "Processing manager assignments for $($usersWithManagers.Count) users"

                    # Group manager assignments into batches
                    $managerBatches = @()
                    $managerBatchSize = [Math]::Min($BatchSize, 20)  # Smaller batches for manager operations

                    for ($i = 0; $i -lt $usersWithManagers.Count; $i += $managerBatchSize) {
                        $batchEnd = [Math]::Min($i + $managerBatchSize - 1, $usersWithManagers.Count - 1)
                        $managerBatches += ,@($usersWithManagers[$i..$batchEnd])
                    }

                    Write-Verbose ("Created $($managerBatches.Count) manager assignment batches of size " +
                        "$managerBatchSize")

                    # Process manager batches with throttling
                    $jobListType = [System.Collections.Generic.List[System.Management.Automation.Job]]
                    $script:ManagerJobs = $jobListType::new()
                    $managerBatchNumber = 0
                    $completedManagerBatches = 0

                    foreach ($batch in $managerBatches) {
                        $managerBatchNumber++

                        # Wait for available slot if at throttle limit
                        while ($script:ManagerJobs.Count -ge $ThrottleLimit) {
                            Start-Sleep -Milliseconds 300

                            # Check for completed jobs
                            $completedJobs = $script:ManagerJobs | Where-Object { $_.State -eq 'Completed' }
                            if ($completedJobs) {
                                foreach ($job in $completedJobs) {
                                    $result = Receive-Job -Job $job
                                    Remove-Job -Job $job

                                    # Aggregate results
                                    $script:ManagersSet += $result.ManagersSet
                                    $script:Errors += $result.Errors

                                    $completedManagerBatches++
                                }

                                # Remove completed jobs from tracking
                                $remainingJobs = $script:ManagerJobs | Where-Object { $_.State -ne 'Completed' }
                                $script:ManagerJobs.Clear()
                                foreach ($job in $remainingJobs) {
                                    $script:ManagerJobs.Add($job)
                                }

                                # Update progress
                                $percentComplete = 85 + (($completedManagerBatches / $managerBatches.Count) * 10)
                                Write-Progress -Activity "Creating Users" -Status ("Manager assignments: " +
                                    "$completedManagerBatches of $($managerBatches.Count) " +
                                    "batches") -PercentComplete $percentComplete
                            }
                        }

                        # Start new manager batch job
                        $jobName = "ManagerBatch_$managerBatchNumber"
                        Write-Verbose "Starting manager batch $managerBatchNumber with $($batch.Count) assignments"

                        $job = Start-Job -Name $jobName -ScriptBlock {
                            param($BatchRecord, $VerbosePreference)

                            # Import required modules in job
                            Import-Module ActiveDirectory -Verbose:$false

                            $batchResults = @{
                                ManagersSet = 0
                                Errors = @()
                            }

                            foreach ($user in $BatchRecord) {
                                try {
                                    # Extract manager name from CN format
                                    $managerName = $user.Manager -replace "^CN=", ""
                                    # Escape single quotes in the name for AD filter
                                    $escapedManagerName = $managerName -replace "'", "''"
                                    $managerUser = Get-ADUser -Filter ("Name -eq " +
                                        "'$escapedManagerName'") -ErrorAction SilentlyContinue

                                    if ($managerUser) {
                                        $setADUserArgs1 = @{
                                            Identity = $user.SamAccountName
                                            Manager  = $managerUser.DistinguishedName
                                        }
                                        Set-ADUser @setADUserArgs1
                                        Write-Verbose "Set manager for $($user.Name): $managerName"
                                        $batchResults.ManagersSet++
                                    }
                                    else {
                                        $batchResults.Errors += "Manager not found for $($user.Name): $managerName"
                                    }
                                }
                                catch {
                                    $batchResults.Errors += ("Manager assignment error for $($user.Name): " +
                                        "$($_.Exception.Message)")
                                }
                            }

                            return $batchResults
                        } -ArgumentList $batch, $VerbosePreference

                        $script:ManagerJobs.Add($job)
                    }

                    # Wait for all manager assignment jobs to complete
                    Write-Verbose "Waiting for all manager assignment jobs to complete..."
                    while ($script:ManagerJobs.Count -gt 0) {
                        Start-Sleep -Milliseconds 300

                        $completedJobs = $script:ManagerJobs | Where-Object { $_.State -eq 'Completed' }
                        if ($completedJobs) {
                            foreach ($job in $completedJobs) {
                                $result = Receive-Job -Job $job
                                Remove-Job -Job $job

                                # Aggregate results
                                $script:ManagersSet += $result.ManagersSet
                                $script:Errors += $result.Errors

                                $completedManagerBatches++
                            }

                            # Remove completed jobs from tracking
                            $remainingJobs = $script:ManagerJobs | Where-Object { $_.State -ne 'Completed' }
                            $script:ManagerJobs.Clear()
                            foreach ($job in $remainingJobs) {
                                $script:ManagerJobs.Add($job)
                            }

                            # Update progress
                            $percentComplete = 85 + (($completedManagerBatches / $managerBatches.Count) * 10)
                            Write-Progress -Activity "Creating Users" -Status ("Manager assignments: " +
                                "$completedManagerBatches of $($managerBatches.Count) " +
                                "batches") -PercentComplete $percentComplete
                        }
                    }

                    Write-Verbose "Manager assignment processing completed"
                } else {
                    Write-Verbose "No users require manager assignments"
                }
            }

            Write-Progress -Activity "Creating Users" -Status "Complete" -PercentComplete 100 -Completed

            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalUsers = $totalUsers
                CreatedUsers = $script:UsersCreated
                SkippedUsers = $script:UsersSkipped
                BatchesProcessed = $userBatches.Count
                BatchSize = $BatchSize
                ThrottleLimit = $ThrottleLimit
                PhotosAdded = if ($IncludePhotos) { $script:PhotosAdded } else { 0 }
                ManagersSet = $script:ManagersSet
                Errors = $script:Errors
            }

            # Display summary
            Write-TestMessage -Message "User Creation Summary (Batch Mode)" -Type Success
            Write-Host "  User Creation Batches: $($results.BatchesProcessed)" -ForegroundColor Cyan
            Write-Host "  Batch Size: $($results.BatchSize)" -ForegroundColor Cyan
            Write-Host "  Users Created: $($results.CreatedUsers)" -ForegroundColor Green
            Write-Host "  Users Skipped: $($results.SkippedUsers)" -ForegroundColor Yellow
            if ($IncludePhotos) {
                Write-Host "  Photos Added: $($results.PhotosAdded)" -ForegroundColor Green
            }
            Write-Host "  Managers Set: $($results.ManagersSet)" -ForegroundColor Green

            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            # Cleanup any remaining jobs on error
            if ($script:ProcessingJobs.Count -gt 0) {
                Write-Verbose ("Cleaning up $($script:ProcessingJobs.Count) user creation background jobs due " +
                    "to error")
                foreach ($job in $script:ProcessingJobs) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
                $script:ProcessingJobs.Clear()
            }

            # Cleanup manager assignment jobs if they exist.
            #
            # Guarded on the variable itself. This used to read
            #   if (Get-Variable -Name 'script:ManagerJobs' -ErrorAction SilentlyContinue
            #       -and $script:ManagerJobs.Count -gt 0)
            # where -and binds as a PARAMETER to Get-Variable rather than as an operator.
            # Get-Variable has no -and, so this line threw "A parameter cannot be found that
            # matches parameter name 'and'" every time the handler ran - replacing the real
            # failure with a confusing one and leaking the jobs it exists to stop. The
            # scope-qualified name would not have resolved through -Name either.
            if ($script:ManagerJobs -and $script:ManagerJobs.Count -gt 0) {
                Write-Verbose ("Cleaning up $($script:ManagerJobs.Count) manager assignment background jobs due " +
                    "to error")
                foreach ($job in $script:ManagerJobs) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
                $script:ManagerJobs.Clear()
            }

            Write-Error "Failed to create users: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestUser - CorrelationId: $correlationId"
    }
}
