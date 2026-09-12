function New-ADEnvironment {
    <#
    .SYNOPSIS
        Creates a complete Active Directory test environment with OUs, users, devices, and groups

    .DESCRIPTION
        This function orchestrates the creation of a comprehensive AD test environment by:
        1. Creating the OU structure
        2. Creating user accounts from CSV data
        3. Creating device objects from CSV data
        4. Creating service accounts from CSV data (with optional SecretStore password storage)
        5. Creating security groups and assigning memberships

        This is the main entry point for setting up the entire test environment.

    .PARAMETER Skip
        Specify which components to skip during creation. Valid values:
        - OUStructure: Skip creating the OU structure (useful if it already exists)
        - Users: Skip creating user accounts
        - Devices: Skip creating device objects
        - ServiceAccounts: Skip creating service accounts
        - Groups: Skip creating security groups

    .PARAMETER WhatIf
        Shows what would be created without making changes

    .PARAMETER ShowProgress
        Display detailed progress information during execution

    .PARAMETER PassThru
        Return the detailed results object. By default, only summary information is displayed.

    .PARAMETER UseSecretStore
        Use PowerShell SecretManagement/SecretStore modules to store service account passwords
        in a secure vault instead of exporting to a plain text file. Will install required modules if not present.

    .PARAMETER VaultName
        Name of the secret vault to use when UseSecretStore is specified. Defaults to "ADTestEnvironment"

    .PARAMETER VaultPassword
        Password for the secret vault when UseSecretStore is specified. If not provided,
        will use "ADTestEnvironmentPassword" as the default to avoid prompting.

    .PARAMETER GlobalVault
        Create SecretStore vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges. Only applies when UseSecretStore is specified.

    .EXAMPLE
        New-ADEnvironment
        Creates the complete test environment

    .EXAMPLE
        New-ADEnvironment -UseSecretStore
        Creates the complete test environment with service account passwords stored in SecretStore vault

    .EXAMPLE
        $vaultPass = ConvertTo-SecureString "VaultPass123!" -AsPlainText -Force
        New-ADEnvironment -UseSecretStore -VaultName "ProdVault" -VaultPassword $vaultPass
        Creates the environment with passwords stored in a custom named vault

    .EXAMPLE
        New-ADEnvironment -UseSecretStore -GlobalVault
        Creates the environment with service account passwords in a global vault (requires admin privileges)

    .EXAMPLE
        New-ADEnvironment -WhatIf
        Shows what would be created without making changes

    .EXAMPLE
        New-ADEnvironment -Skip Devices,Groups
        Creates only OUs, users, and service accounts

    .EXAMPLE
        New-ADEnvironment -Skip ServiceAccounts
        Creates OUs, users, devices, and groups but skips service accounts

    .EXAMPLE
        New-ADEnvironment -Skip OUStructure,Users,Devices,ServiceAccounts,Groups -WhatIf
        Shows what would happen if all components were skipped (essentially a no-op)

    .OUTPUTS
        Hashtable containing summary of operations performed

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2025-08-05

        REQUIREMENTS:
        - Active Directory PowerShell module
        - Domain administrator privileges
        - CSV data files in Data folder

        SECRETSTORE FEATURES:
        - Use -UseSecretStore to store service account passwords in an encrypted vault
        - Automatically installs required SecretManagement/SecretStore modules if not present
        - Creates computer-level vault for shared access (when run as administrator)
        - Retrieve passwords later using Get-ADTestPasswordFromVault function


    .LINK
        New-ADTestOUStructure
        New-ADTestUser
        New-ADTestDevice
        New-ADTestServiceAccount
        New-ADTestSecurityGroups
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [ValidateSet('OUStructure', 'Users', 'Devices', 'ServiceAccounts', 'Groups',
            'PasswordPolicies', 'Dns')]
        [string[]]$Skip = @(),

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$GlobalVault,

        # Opt-in, and deliberately not part of -Skip. -Skip turns off things that are on by
        # default; this turns on something that is off by default, because it writes access
        # control entries and plants a SID that resolves to nothing. That should be asked
        # for, never inherited from a default.
        [Parameter()]
        [switch]$IncludeEdgeCase
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADEnvironment - CorrelationId: $correlationId"

        # Test prerequisites
        if (-not (Test-ADTestPrerequisite -CheckDataFiles)) {
            throw "Prerequisites not met for AD test environment creation"
        }
    }

    process {
        try {
            Write-TestMessage -Message "Active Directory Test Environment Creation" -Type Header

            $results = @{
                CorrelationId = $correlationId
                StartTime = Get-Date
                Operations = @{
                    OUStructure = @{ Attempted = $false; Success = $false; Results = $null }
                    Users = @{ Attempted = $false; Success = $false; Results = $null }
                    Devices = @{ Attempted = $false; Success = $false; Results = $null }
                    ServiceAccounts = @{ Attempted = $false; Success = $false; Results = $null }
                    Groups = @{ Attempted = $false; Success = $false; Results = $null }
                    PasswordPolicies = @{ Attempted = $false; Success = $false; Results = $null }
                    Dns = @{ Attempted = $false; Success = $false; Results = $null }
                    EdgeCases = @{ Attempted = $false; Success = $false; Results = $null }
                }
                Summary = @{
                    TotalOperations = 0
                    SuccessfulOperations = 0
                    FailedOperations = 0
                }
            }

            # Step 1: Create OU Structure
            Write-Verbose "Skip contains: $($Skip -join ', ')"

            # Raised when the domain controller stops answering part way through. Every step
            # after it would fail the same way and report the same error once per object, so
            # the run stops and says why instead: twenty-five identical failures followed by
            # a half-built directory buries the one thing that went wrong.
            #
            # A hashtable rather than a plain variable because the script block below has to
            # be able to set it, and an assignment inside one makes a local copy.
            $seedState = @{ DirectoryLost = $false }
            $abortIfDirectoryLost = {
                param($stepName)
                if ($seedState.DirectoryLost) { return $true }
                if (Test-ADTestDirectoryReachable) { return $false }
                $seedState.DirectoryLost = $true
                Write-TestMessage -Message ("The domain controller stopped answering during " +
                    "$stepName. Stopping here rather than failing every remaining step against " +
                    'a directory that is not there. Nothing already created has been removed; ' +
                    'run Remove-TestEnvironment once it is back.') -Type Error
                return $true
            }
            if ('OUStructure' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 1: Creating OU Structure" -Type Info
                $results.Operations.OUStructure.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("OU Structure", "Create AD Test OU Structure")) {
                        $ouResults = New-ADTestOUStructure
                        $results.Operations.OUStructure.Success = $true
                        $results.Operations.OUStructure.Results = $ouResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Created $($ouResults.Created.Count) OUs"
                            if ($ouResults.Errors.Count -gt 0) {
                                Write-Verbose "$($ouResults.Errors.Count) errors encountered"
                            }
                        }
                    }
                } catch {
                    $results.Operations.OUStructure.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "OU Structure creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-TestMessage -Message "Step 1: Skipping OU Structure (as requested)" -Type Warning
            }

            # Step 2: Create Users
            if ('Users' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 2: Creating User Accounts" -Type Info
                $results.Operations.Users.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("User Accounts", "Create AD Test Users")) {
                        $userResults = New-ADTestUser
                        $results.Operations.Users.Success = $true
                        $results.Operations.Users.Results = $userResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($userResults.TotalUsers) users"
                            Write-Verbose "Created $($userResults.CreatedUsers) new users"
                        }
                    }
                } catch {
                    $results.Operations.Users.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "User creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the users'
                }
            } else {
                Write-TestMessage -Message "Step 2: Skipping User Accounts (as requested)" -Type Warning
            }

            # Step 3: Create Devices
            if ('Devices' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 3: Creating Device Objects" -Type Info
                $results.Operations.Devices.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Device Objects", "Create AD Test Devices")) {
                        $deviceResults = New-ADTestDevice
                        $results.Operations.Devices.Success = $true
                        $results.Operations.Devices.Results = $deviceResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($deviceResults.TotalDevices) devices"
                            Write-Verbose "Created $($deviceResults.CreatedDevices) new devices"
                        }
                    }
                } catch {
                    $results.Operations.Devices.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Device creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the devices'
                }
            } else {
                Write-TestMessage -Message "Step 3: Skipping Device Objects (as requested)" -Type Warning
            }

            # Step 4: Create Service Accounts
            if ('ServiceAccounts' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 4: Creating Service Accounts" -Type Info
                $results.Operations.ServiceAccounts.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Service Accounts", "Create AD Test Service Accounts")) {
                        # Create service accounts (simplified - no SecretStore orchestration)
                        $serviceAccountResults = New-ADTestServiceAccount -PassThru
                        if (-not (Test-ADTestDirectoryReachable)) { $null = & $abortIfDirectoryLost 'the service accounts' }
                        $results.Operations.ServiceAccounts.Success = $true
                        $results.Operations.ServiceAccounts.Results = $serviceAccountResults
                        $results.Summary.SuccessfulOperations++

                        # Handle SecretStore orchestration separately if requested
                        if ($UseSecretStore -and $serviceAccountResults.PasswordData.Count -gt 0) {
                            try {
                                $orchestrationParams = @{
                                    PasswordData = $serviceAccountResults.PasswordData
                                    VaultName = $VaultName
                                    GlobalVault = $GlobalVault
                                    CorrelationId = $correlationId
                                }

                                if ($VaultPassword) {
                                    $orchestrationParams.VaultPassword = $VaultPassword
                                }

                                $secretStoreResult = Invoke-ADTestSecretStoreOrchestration @orchestrationParams

                                # Add SecretStore results to service account results
                                $storeProp = @{
                                    NotePropertyName  = 'SecretStoreResult'
                                    NotePropertyValue = $secretStoreResult
                                    Force             = $true
                                }
                                $serviceAccountResults | Add-Member @storeProp

                                $useProp = @{
                                    NotePropertyName  = 'UseSecretStore'
                                    NotePropertyValue = $true
                                    Force             = $true
                                }
                                $serviceAccountResults | Add-Member @useProp

                                $vaultProp = @{
                                    NotePropertyName  = 'VaultName'
                                    NotePropertyValue = $VaultName
                                    Force             = $true
                                }
                                $serviceAccountResults | Add-Member @vaultProp

                                if ($secretStoreResult.Errors.Count -gt 0) {
                                    Write-Warning ("SecretStore orchestration completed with errors: " +
                                        "$($secretStoreResult.Errors -join '; ')")
                                    # Fall back to file export
                                    $exportPasswordDocumentationArgs1 = @{
                                        PasswordData = $serviceAccountResults.PasswordData
                                        FilePrefix   = "ServiceAccountPW"
                                    }
                                    $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs1
                                    Write-Warning "Passwords exported to file as fallback: $passwordFile"
                                    $fileProp = @{
                                        NotePropertyName  = 'PasswordFile'
                                        NotePropertyValue = $passwordFile
                                        Force             = $true
                                    }
                                    $serviceAccountResults | Add-Member @fileProp
                                }
                            }
                            catch {
                                Write-Warning "SecretStore orchestration failed: $($_.Exception.Message)"
                                # Fall back to file export
                                $exportPasswordDocumentationArgs2 = @{
                                    PasswordData = $serviceAccountResults.PasswordData
                                    FilePrefix   = "ServiceAccountPW"
                                }
                                $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs2
                                Write-Warning "Passwords exported to file as fallback: $passwordFile"
                                $fileProp = @{
                                    NotePropertyName  = 'PasswordFile'
                                    NotePropertyValue = $passwordFile
                                    Force             = $true
                                }
                                $serviceAccountResults | Add-Member @fileProp
                            }
                        }
                        elseif ($serviceAccountResults.PasswordData.Count -gt 0) {
                            # Export to file when not using SecretStore
                            $exportPasswordDocumentationArgs3 = @{
                                PasswordData = $serviceAccountResults.PasswordData
                                FilePrefix   = "ServiceAccountPW"
                            }
                            $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs3
                            $fileProp = @{
                                NotePropertyName  = 'PasswordFile'
                                NotePropertyValue = $passwordFile
                                Force             = $true
                            }
                            $serviceAccountResults | Add-Member @fileProp
                        }

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($serviceAccountResults.TotalAccounts) service accounts"
                            Write-Verbose "Created $($serviceAccountResults.CreatedAccounts) new service accounts"

                            if ($UseSecretStore -and $serviceAccountResults.SecretStoreResult) {
                                Write-Verbose ("Stored $($serviceAccountResults.SecretStoreResult.TotalStored) " +
                                    "passwords in vault: $VaultName")
                            }
                            elseif ($serviceAccountResults.PasswordFile) {
                                Write-Verbose "Password file created: $($serviceAccountResults.PasswordFile)"
                            }
                        }
                    }
                } catch {
                    $results.Operations.ServiceAccounts.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Service account creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the service accounts'
                }
                # The companion policy carries the deny-logon rights the service accounts
                # are documented to have and that New-ADUser cannot express. It only makes
                # sense once the accounts it names exist, so it runs here rather than as a
                # step of its own, and a failure is a warning: the accounts are still valid
                # test data without it, and the environment should not fail over a policy.
                try {
                    $policyResult = New-ADTestGroupPolicy -PassThru
                    $results.Operations.ServiceAccounts.Policy = $policyResult

                    foreach ($policyWarning in @($policyResult.Warnings)) {
                        Write-Warning $policyWarning
                    }
                }
                catch {
                    Write-Warning "Deny-logon policy not created: $($_.Exception.Message)"
                }
            } else {
                Write-TestMessage -Message "Step 4: Skipping Service Accounts (as requested)" -Type Warning
            }

            # Step 5: Create Security Groups
            if ('Groups' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 5: Creating Security Groups" -Type Info
                $results.Operations.Groups.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Security Groups", "Create AD Test Security Groups")) {
                        $groupResults = New-ADTestSecurityGroups
                        $results.Operations.Groups.Success = $true
                        $results.Operations.Groups.Results = $groupResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($groupResults.TotalGroups) groups"
                            Write-Verbose "Created $($groupResults.CreatedGroups) new groups"
                            Write-Verbose "Added $($groupResults.MembersAdded) group members"
                        }
                    }
                } catch {
                    $results.Operations.Groups.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Security group creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the security groups'
                }
            } else {
                Write-TestMessage -Message "Step 5: Skipping Security Groups (as requested)" -Type Warning
            }

            # Step 6: Fine-grained password policies
            #
            # After the groups, because each policy is applied to one and a policy applied to
            # nothing governs nobody.
            if ('PasswordPolicies' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 6: Creating Password Policies" -Type Info
                $results.Operations.PasswordPolicies.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Password Policies", "Create AD Fine-Grained Password Policies")) {
                        $policyResults = New-ADTestPasswordPolicy -PassThru
                        $results.Operations.PasswordPolicies.Success = @($policyResults.Errors).Count -eq 0
                        $results.Operations.PasswordPolicies.Results = $policyResults
                        if ($results.Operations.PasswordPolicies.Success) {
                            $results.Summary.SuccessfulOperations++
                        }
                        else {
                            $results.Summary.FailedOperations++
                        }

                        if ($ShowProgress) {
                            Write-Verbose ("Created $($policyResults.CreatedPolicies) policies, " +
                                "applied to $($policyResults.SubjectsApplied) groups")
                        }
                    }
                } catch {
                    $results.Operations.PasswordPolicies.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Password policy creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the password policies'
                }
            } else {
                Write-TestMessage -Message "Step 6: Skipping Password Policies (as requested)" -Type Warning
            }

            # Step 7: DNS zones and records
            #
            # After the devices, because a record is written for every device that carries an
            # address. A domain without the integrated DNS role reports a warning here and the
            # seeded computers simply do not resolve, which is what they did before this step
            # existed.
            if ('Dns' -notin $Skip -and -not $seedState.DirectoryLost) {
                Write-TestMessage -Message "Step 7: Creating DNS Zones and Records" -Type Info
                $results.Operations.Dns.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("DNS Zones", "Create AD Test DNS Zones and Records")) {
                        $dnsResults = New-ADTestDnsZone -PassThru -ShowProgress:$ShowProgress
                        $results.Operations.Dns.Success = @($dnsResults.Errors).Count -eq 0
                        $results.Operations.Dns.Results = $dnsResults
                        if ($results.Operations.Dns.Success) {
                            $results.Summary.SuccessfulOperations++
                        }
                        else {
                            $results.Summary.FailedOperations++
                        }

                        if ($ShowProgress) {
                            Write-Verbose ("Created $($dnsResults.ZonesCreated) zones, " +
                                "$($dnsResults.DeviceRecords) device records")
                        }
                    }
                } catch {
                    $results.Operations.Dns.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "DNS creation failed: $($_.Exception.Message)"
                    $null = & $abortIfDirectoryLost 'the DNS zones'
                }
            } else {
                Write-TestMessage -Message "Step 7: Skipping DNS Zones (as requested)" -Type Warning
            }

            # Step 8: Create edge cases (opt-in only)
            #
            # Last, because the delegation and orphaned-SID states attach to objects the
            # earlier steps create, and the ambiguous-name group has to be able to collide
            # with a directory that already exists.
            if ($IncludeEdgeCase) {
                Write-TestMessage -Message "Step 8: Creating Edge Cases" -Type Info
                $results.Operations.EdgeCases.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Edge Cases", "Create AD Test Edge Cases")) {
                        $edgeResults = New-ADTestEdgeCase -PassThru -Confirm:$false
                        $results.Operations.EdgeCases.Success = $true
                        $results.Operations.EdgeCases.Results = $edgeResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Created $(@($edgeResults.Created).Count) edge case states"
                        }
                    }
                } catch {
                    $results.Operations.EdgeCases.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Edge case creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-TestMessage -Message ("Step 8: Skipping Edge Cases (pass -IncludeEdgeCase to create " +
                    "them)") -Type Info
            }

            # Final Summary
            $results.EndTime = Get-Date
            $results.Duration = $results.EndTime - $results.StartTime

            Write-TestMessage -Message "Environment Creation Summary" -Type Header
            $completed = "Operations Completed: $($results.Summary.SuccessfulOperations)/" +
                "$($results.Summary.TotalOperations)"
            Write-Host $completed -ForegroundColor Green
            Write-Host "Duration: $($results.Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

            if ($results.Summary.FailedOperations -gt 0) {
                Write-Warning "Failed Operations: $($results.Summary.FailedOperations)"
                Write-Warning "Check the results object for detailed error information."

                # Not "complete". A closing line that reports success regardless of what
                # happened is the last thing a person reads, and it was overriding the warnings
                # immediately above it. The Okta provider had the same line and a live run
                # there announced success over four failed steps.
                Write-TestMessage -Message ("Test environment creation finished with " +
                    "$($results.Summary.FailedOperations) failed operation(s).") -Type Error
            }
            else {
                Write-TestMessage -Message "Test environment creation complete!" -Type Success
            }

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            Write-Error "Failed to create test environment: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADEnvironment - CorrelationId: $correlationId"
    }
}
