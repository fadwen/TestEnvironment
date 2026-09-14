function New-ADEnvironment {
    <#
    .SYNOPSIS
        Creates a complete Active Directory test environment with OUs, users, devices, and groups

    .DESCRIPTION
        This function orchestrates the creation of a comprehensive AD test environment by:
        1. Creating the OU structure
        2. Creating user accounts from CSV data
        3. Creating device objects from CSV data
        4. Creating service accounts from CSV data (with optional SecretStore password storage),
           and the deny-logon policy that names them
        5. Creating security groups and assigning memberships
        6. Creating fine-grained password policies, applied to the groups
        7. Creating the DNS zones and the records for the devices
        8. Creating the edge-case states, only with -IncludeEdgeCase

        The steps are held as a table in dependency order, and every step is attempted, recorded
        and reported the same way. A step that throws is recorded as failed and the run goes on,
        unless the domain controller stopped answering during it, in which case the run stops and
        says so once. This is the main entry point for setting up the entire test environment.

    .PARAMETER Skip
        Specify which components to skip during creation. Valid values:
        - OUStructure: Skip creating the OU structure (useful if it already exists)
        - Users: Skip creating user accounts
        - Devices: Skip creating device objects
        - ServiceAccounts: Skip creating service accounts
        - Groups: Skip creating security groups
        - PasswordPolicies: Skip creating fine-grained password policies
        - Dns: Skip creating the DNS zones and records

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

    .PARAMETER Tier
        Seed only the Core users (the eleven people every provider holds) or only the Bulk users
        (the three hundred generated for volume). Both by default. Every other object type is
        hand-designed and seeded whole; a group rule that names a person left out simply finds
        nobody.

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

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

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

            # The vault the service account passwords go to, bound here rather than read inside
            # the step's script block, so the parameters are visibly used.
            $vault = @{
                UseSecretStore = [bool]$UseSecretStore
                VaultName      = $VaultName
                GlobalVault    = [bool]$GlobalVault
                VaultPassword  = $VaultPassword
            }
            $edgeCasesWanted = [bool]$IncludeEdgeCase
            $userArguments = @{ PassThru = $true }
            if ($Tier) { $userArguments['Tier'] = $Tier }

            # The service accounts are the one step with an epilogue: their passwords go to the
            # vault when asked, and to a file otherwise or when the vault would not take them.
            # Kept beside the step table rather than in it so the table stays one screen.
            $keepServiceAccountPassword = {
                param($serviceAccountResults)

                if ($vault.UseSecretStore -and $serviceAccountResults.PasswordData.Count -gt 0) {
                    try {
                        $orchestrationParams = @{
                            PasswordData = $serviceAccountResults.PasswordData
                            VaultName = $vault.VaultName
                            GlobalVault = $vault.GlobalVault
                            CorrelationId = $correlationId
                        }
                        if ($vault.VaultPassword) {
                            $orchestrationParams.VaultPassword = $vault.VaultPassword
                        }

                        $secretStoreResult = Invoke-ADTestSecretStoreOrchestration @orchestrationParams

                        $serviceAccountResults | Add-Member -NotePropertyName 'SecretStoreResult' -NotePropertyValue $secretStoreResult -Force
                        $serviceAccountResults | Add-Member -NotePropertyName 'UseSecretStore' -NotePropertyValue $true -Force
                        $serviceAccountResults | Add-Member -NotePropertyName 'VaultName' -NotePropertyValue $vault.VaultName -Force

                        if ($secretStoreResult.Errors.Count -gt 0) {
                            Write-Warning ("SecretStore orchestration completed with errors: " +
                                "$($secretStoreResult.Errors -join '; ')")
                            $passwordFile = Export-ADTestPasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix 'ServiceAccountPW'
                            Write-Warning "Passwords exported to file as fallback: $passwordFile"
                            $serviceAccountResults | Add-Member -NotePropertyName 'PasswordFile' -NotePropertyValue $passwordFile -Force
                        }
                    }
                    catch {
                        Write-Warning "SecretStore orchestration failed: $($_.Exception.Message)"
                        $passwordFile = Export-ADTestPasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix 'ServiceAccountPW'
                        Write-Warning "Passwords exported to file as fallback: $passwordFile"
                        $serviceAccountResults | Add-Member -NotePropertyName 'PasswordFile' -NotePropertyValue $passwordFile -Force
                    }
                }
                elseif ($serviceAccountResults.PasswordData.Count -gt 0) {
                    $passwordFile = Export-ADTestPasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix 'ServiceAccountPW'
                    $serviceAccountResults | Add-Member -NotePropertyName 'PasswordFile' -NotePropertyValue $passwordFile -Force
                }
            }

            # The companion policy carries the deny-logon rights the service accounts are
            # documented to have and that New-ADUser cannot express. It only makes sense once
            # the accounts it names exist, so it runs right after them rather than as a step of
            # its own, only when the accounts step succeeded - not after it threw, and not
            # under -WhatIf, where nothing it could name exists - and a failure is a warning:
            # the accounts are still valid test data without it, and the environment should
            # not fail over a policy.
            $denyLogonPolicy = {
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
            }

            # Each step is the same shape: announce, ask ShouldProcess, run, record, keep going.
            # Declared as data, as the Okta and Entra orchestrators are, so the order - the part
            # of this function that matters - is written once and read on one screen instead of
            # being inferred from eight copies of the same try/catch.
            #
            #   Key        the -Skip name and the key under Operations
            #   Title      announced when the step runs; Skipped names it in the skip message
            #   Target,    the ShouldProcess pair, so a -WhatIf transcript reads as it always has
            #   Action
            #   Run        the call; what it returns is the step's Results
            #   Failed     what the error names when the call throws
            #   Lost       what the abort message names when the domain controller stopped
            #              answering during the step; absent for the one step whose failure is
            #              never that, because it is the first thing that touches the directory
            #   ByErrors   Success reads the Errors the result carries rather than "did not
            #              throw", for the steps that collect their failures and return
            #   Then       runs after a successful call, inside the step's own try
            #   After      runs after the step is recorded, only when it succeeded
            #   Wanted     an opt-in step runs only when this says so, and says why otherwise
            #   Report     what -ShowProgress writes, one line per string
            $steps = @(
                @{
                    Key = 'OUStructure'; Title = 'Step 1: Creating OU Structure'; Skipped = 'OU Structure'
                    Target = 'OU Structure'; Action = 'Create AD Test OU Structure'
                    Run = { New-ADTestOUStructure -PassThru }
                    Failed = 'OU Structure creation'
                    Report = { param($r)
                        "Created $($r.Created.Count) OUs"
                        if ($r.Errors.Count -gt 0) { "$($r.Errors.Count) errors encountered" }
                    }
                }
                @{
                    Key = 'Users'; Title = 'Step 2: Creating User Accounts'; Skipped = 'User Accounts'
                    Target = 'User Accounts'; Action = 'Create AD Test Users'
                    Run = { New-ADTestUser @userArguments }
                    Failed = 'User creation'; Lost = 'the users'
                    Report = { param($r) "Processed $($r.TotalUsers) users"; "Created $($r.CreatedUsers) new users" }
                }
                @{
                    Key = 'Devices'; Title = 'Step 3: Creating Device Objects'; Skipped = 'Device Objects'
                    Target = 'Device Objects'; Action = 'Create AD Test Devices'
                    Run = { New-ADTestDevice -PassThru }
                    Failed = 'Device creation'; Lost = 'the devices'
                    Report = { param($r) "Processed $($r.TotalDevices) devices"; "Created $($r.CreatedDevices) new devices" }
                }
                @{
                    Key = 'ServiceAccounts'; Title = 'Step 4: Creating Service Accounts'; Skipped = 'Service Accounts'
                    Target = 'Service Accounts'; Action = 'Create AD Test Service Accounts'
                    Run = {
                        $serviceAccountResults = New-ADTestServiceAccount -PassThru
                        # This step collects its failures rather than throwing, so a directory
                        # that went away during it is only visible by asking.
                        if (-not (Test-ADTestDirectoryReachable)) { $null = & $abortIfDirectoryLost 'the service accounts' }
                        $serviceAccountResults
                    }
                    Failed = 'Service account creation'; Lost = 'the service accounts'
                    Then = { param($r) & $keepServiceAccountPassword $r }
                    After = { & $denyLogonPolicy }
                    Report = { param($r)
                        "Processed $($r.TotalAccounts) service accounts"
                        "Created $($r.CreatedAccounts) new service accounts"
                        if ($vault.UseSecretStore -and $r.SecretStoreResult) {
                            "Stored $($r.SecretStoreResult.TotalStored) passwords in vault: $($vault.VaultName)"
                        }
                        elseif ($r.PasswordFile) {
                            "Password file created: $($r.PasswordFile)"
                        }
                    }
                }
                @{
                    Key = 'Groups'; Title = 'Step 5: Creating Security Groups'; Skipped = 'Security Groups'
                    Target = 'Security Groups'; Action = 'Create AD Test Security Groups'
                    Run = { New-ADTestSecurityGroups -PassThru }
                    Failed = 'Security group creation'; Lost = 'the security groups'
                    Report = { param($r)
                        "Processed $($r.TotalGroups) groups"
                        "Created $($r.CreatedGroups) new groups"
                        "Added $($r.MembersAdded) group members"
                    }
                }
                # After the groups, because each policy is applied to one and a policy applied
                # to nothing governs nobody.
                @{
                    Key = 'PasswordPolicies'; Title = 'Step 6: Creating Password Policies'; Skipped = 'Password Policies'
                    Target = 'Password Policies'; Action = 'Create AD Fine-Grained Password Policies'
                    Run = { New-ADTestPasswordPolicy -PassThru }
                    Failed = 'Password policy creation'; Lost = 'the password policies'; ByErrors = $true
                    Report = { param($r) "Created $($r.CreatedPolicies) policies, applied to $($r.SubjectsApplied) groups" }
                }
                # After the devices, because a record is written for every device that carries
                # an address. A domain without the integrated DNS role reports a warning here
                # and the seeded computers simply do not resolve, which is what they did before
                # this step existed.
                @{
                    Key = 'Dns'; Title = 'Step 7: Creating DNS Zones and Records'; Skipped = 'DNS Zones'
                    Target = 'DNS Zones'; Action = 'Create AD Test DNS Zones and Records'
                    Run = { New-ADTestDnsZone -PassThru -ShowProgress:$ShowProgress }
                    Failed = 'DNS creation'; Lost = 'the DNS zones'; ByErrors = $true
                    Report = { param($r) "Created $($r.ZonesCreated) zones, $($r.DeviceRecords) device records" }
                }
                # Last, because the delegation and orphaned-SID states attach to objects the
                # earlier steps create, and the ambiguous-name group has to be able to collide
                # with a directory that already exists. Opt-in, and deliberately not part of
                # -Skip: see the parameter.
                @{
                    Key = 'EdgeCases'; Title = 'Step 8: Creating Edge Cases'; Skipped = 'Edge Cases'
                    Target = 'Edge Cases'; Action = 'Create AD Test Edge Cases'
                    Wanted = { $edgeCasesWanted }
                    NotWanted = 'Step 8: Skipping Edge Cases (pass -IncludeEdgeCase to create them)'
                    Run = { New-ADTestEdgeCase -PassThru -Confirm:$false }
                    Failed = 'Edge case creation'
                    Report = { param($r) "Created $(@($r.Created).Count) edge case states" }
                }
            )

            $stepNumber = 0
            foreach ($step in $steps) {
                $stepNumber++
                $operation = $results.Operations[$step.Key]

                if ($step.ContainsKey('Wanted') -and -not (& $step.Wanted)) {
                    Write-TestMessage -Message $step.NotWanted -Type Info
                    continue
                }
                if ($step.Key -in $Skip) {
                    Write-TestMessage -Message "Step $stepNumber`: Skipping $($step.Skipped) (as requested)" -Type Warning
                    continue
                }
                if ($seedState.DirectoryLost) {
                    Write-TestMessage -Message ("Step $stepNumber`: Not attempting $($step.Skipped); the domain " +
                        'controller stopped answering.') -Type Warning
                    continue
                }

                Write-TestMessage -Message $step.Title -Type Info
                $operation.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess($step.Target, $step.Action)) {
                        $stepResult = & $step.Run
                        $operation.Results = $stepResult
                        $operation.Success = if ($step.ByErrors) { @($stepResult.Errors).Count -eq 0 } else { $true }
                        if ($operation.Success) {
                            $results.Summary.SuccessfulOperations++
                        }
                        else {
                            $results.Summary.FailedOperations++
                        }

                        if ($step.Then) { & $step.Then $stepResult }

                        if ($ShowProgress) {
                            foreach ($line in @(& $step.Report $stepResult)) { Write-Verbose $line }
                        }
                    }
                }
                catch {
                    $operation.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "$($step.Failed) failed: $($_.Exception.Message)"
                    if ($step.Lost) { $null = & $abortIfDirectoryLost $step.Lost }
                }

                if ($step.After -and $operation.Success) { & $step.After }
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
