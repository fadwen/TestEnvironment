function New-ADTestServiceAccount {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates Active Directory test service accounts from CSV data
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Collections.Hashtable])]
    param(
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
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestServiceAccount - CorrelationId: $correlationId"

        # Get data paths
        $dataPath = Get-ADTestDataPath
        $serviceAccountsCSV = Join-Path $dataPath "ADServiceAccounts.csv"

        # Verify prerequisites
        if (-not (Test-Path $serviceAccountsCSV)) {
            throw "ADServiceAccounts.csv not found at: $dataPath"
        }

        # Get domain information
        $domain = Get-ADTestDomain

        # Counters
        $script:ServiceAccountsCreated = 0
        $script:ServiceAccountsSkipped = 0
        $script:Errors = @()
        $script:PasswordExports = @()
    }

    process {
        # {prefix} and {zone} in an SPN become the session's prefix and the seed's forward
        # DNS zone, so a principal name resolves to a computer this module created.
        $spnZone = Get-ADTestSeedZone
        $spnPrefix = (Get-ADTestSeedMarker).Prefix.ToLowerInvariant()
        $resolveSpn = {
            param($template)
            ([string]$template).Replace('{prefix}', $spnPrefix).Replace('{zone}', $spnZone.Forward)
        }
        try {
            Write-TestMessage -Message "Creating Active Directory Test Service Accounts" -Type Header
            Write-TestMessage -Message "Loading service account data from CSV..." -Type Info

            # Import service account data
            $serviceAccounts = Import-Csv $serviceAccountsCSV
            Write-Verbose "Loaded $($serviceAccounts.Count) service accounts from CSV"

            $totalAccounts = $serviceAccounts.Count
            $currentAccount = 0

            Write-TestMessage -Message "Processing $totalAccounts service accounts..." -Type Info

            foreach ($serviceAccount in $serviceAccounts) {
                $currentAccount++
                $percentComplete = ($currentAccount / $totalAccounts) * 100

                Write-Progress -Activity "Creating Service Accounts" -Status ("Processing " +
                    "$($serviceAccount.SamAccountName)") -PercentComplete $percentComplete

                try {
                    # Skip if service account already exists
                    $existingAccount = Get-ADUser -Filter ("SamAccountName -eq " +
                        "'$($serviceAccount.SamAccountName)'") -ErrorAction SilentlyContinue
                    if ($existingAccount) {
                        Write-Verbose "Service account $($serviceAccount.SamAccountName) already exists, skipping"
                        $script:ServiceAccountsSkipped++
                        continue
                    }

                    # Generate cryptographically secure password. The plain form is kept
                    # only long enough to record it in the export below, which is the whole
                    # point of the export - an operator has to be able to read these back.
                    $password = New-TestPassword -Length 16
                    $securePassword = ConvertTo-TestSecureString -PlainText $password

                    # Store password for export
                    $newPasswordExportEntryArgs1 = @{
                        ServiceAccountName = $serviceAccount.SamAccountName
                        Password           = $password
                        Description        = $serviceAccount.Description
                    }
                    # Collected, not discarded. This used to call the builder and throw the
                    # result away, which did two things: the password documentation had
                    # nothing to write, so it never wrote any; and the entry object went to
                    # the output stream instead, so -PassThru returned twenty-five of them
                    # followed by the results object. The caller then read .PasswordData off
                    # an array, got a null per entry, and the export refused the collection.
                    $script:PasswordExports += New-ADTestPasswordExportEntry @newPasswordExportEntryArgs1

                    # Get manager if specified
                    $manager = $null
                    if (-not [string]::IsNullOrWhiteSpace($serviceAccount.Manager)) {
                        # Handle both DN format (CN=Name) and plain name format
                        $managerName = $serviceAccount.Manager
                        if ($managerName.StartsWith('CN=')) {
                            $managerName = $managerName.Substring(3)  # Remove 'CN=' prefix
                        }

                        $manager = Get-ADUser -Filter "Name -eq '$managerName'" -ErrorAction SilentlyContinue
                        if (-not $manager) {
                            Write-Warning ("Manager '$managerName' not found for service account " +
                                "$($serviceAccount.SamAccountName)")
                        }
                    }

                    # Determine OU path
                    $ouPath = "OU=ServiceAccounts,OU=$($script:ADTestRootName),$($domain.DomainDN)"

                    # Verify OU exists
                    try {
                        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Warning ("OU not found: $ouPath. Skipping service account creation for " +
                            "$($serviceAccount.SamAccountName). Please ensure OU structure is created first.")
                        $script:ServiceAccountsSkipped++
                        continue
                    }

                    # Generate dynamic email address
                    $dynamicEmail = if ([string]::IsNullOrWhiteSpace($serviceAccount.mail)) {
                        "$($serviceAccount.SamAccountName)@$($domain.DNSName)"
                    } else {
                        "$($serviceAccount.mail)@$($domain.DNSName)"
                    }

                    # A service account is not a person, so it takes the prefix even though the
                    # seeded human users do not. On the name and display name only: it is a user
                    # object, and a user's sAMAccountName is capped at 20 characters, which
                    # 'ZZ-TEST-' plus a service account name overruns.
                    $seed = Get-ADTestSeedMarker
                    $prefixedName = '{0}{1}' -f $seed.Prefix, $serviceAccount.Name

                    $accountParams = @{
                        Name = $prefixedName
                        SamAccountName = $serviceAccount.SamAccountName
                        UserPrincipalName = "$($serviceAccount.SamAccountName)@$($domain.DNSName)"
                        EmailAddress = $dynamicEmail
                        GivenName = $serviceAccount.GivenName
                        Surname = $serviceAccount.Surname
                        DisplayName = $prefixedName

                        # Description stays exactly what the CSV says; the seed tag goes in
                        # adminDescription, which nothing else in the directory writes.
                        Description = $serviceAccount.Description
                        OtherAttributes = @{ adminDescription = $seed.Tag }
                        Department = $serviceAccount.Department
                        Title = $serviceAccount.Title
                        Office = $serviceAccount.Office
                        StreetAddress = $serviceAccount.StreetAddress
                        City = $serviceAccount.City
                        State = $serviceAccount.State
                        PostalCode = $serviceAccount.PostalCode
                        AccountPassword = $securePassword
                        Enabled = $true
                        CannotChangePassword = $true
                        PasswordNeverExpires = $true
                        Path = $ouPath
                    }

                    # A service principal name is what makes a service account reachable over
                    # Kerberos, and it is what a Kerberoasting review looks for. Eight of the
                    # seeded accounts hold one and the rest hold none, which is the proportion
                    # a real domain has and gives a review something to discriminate on. The
                    # host part names a seeded server inside the seed's own DNS zone.
                    if ($serviceAccount.ServicePrincipalNames) {
                        $accountParams.ServicePrincipalNames = @(
                            $serviceAccount.ServicePrincipalNames -split ';' |
                                Where-Object { $_ } |
                                ForEach-Object { & $resolveSpn $_ }
                        )
                    }

                    # Add manager if found (only add parameter if manager exists)
                    if ($manager) {
                        $accountParams.Manager = $manager.DistinguishedName
                        Write-Verbose "Setting manager for $($serviceAccount.SamAccountName): $($manager.Name)"
                    } else {
                        Write-Verbose "No manager specified or found for $($serviceAccount.SamAccountName)"
                    }

                    # Create service account
                    if ($PSCmdlet.ShouldProcess($serviceAccount.SamAccountName, "Create AD Service Account")) {
                        Write-Verbose "Creating service account: $($serviceAccount.SamAccountName)"
                        $newAccount = New-ADUser @accountParams -PassThru

                        # Set additional properties that require the account to exist
                        Set-ADUser -Identity $newAccount.DistinguishedName -SmartcardLogonRequired $false

                        # These accounts are NOT denied interactive logon. The previous code
                        # built an array of SeDeny*LogonRight names here and then discarded
                        # it, so the comment claimed a hardening step that never ran. Those
                        # are LSA account rights, not AD attributes: they are granted per
                        # machine, so a domain-wide equivalent means a GPO ("Deny log on
                        # locally" and friends) with these accounts as members, not anything
                        # New-ADUser or Set-ADUser can express. Left as a documented gap
                        # rather than a line of code that looks like it does the job.
                        Write-Verbose ("Service account $($serviceAccount.SamAccountName) " +
                            'created; deny-logon rights are not applied - see the GPO note')

                        # Constrained delegation, set after creation because the attribute
                        # is not one New-ADUser accepts. Only constrained: unconstrained
                        # delegation is a live weakness rather than inert test data, so this
                        # module never seeds it and there is no switch to ask for it.
                        if ($serviceAccount.DelegateTo) {
                            $targets = @($serviceAccount.DelegateTo -split ';' |
                                    Where-Object { $_ } | ForEach-Object { & $resolveSpn $_ })
                            try {
                                Set-ADUser -Identity $newAccount.DistinguishedName `
                                    -Add @{ 'msDS-AllowedToDelegateTo' = $targets } -ErrorAction Stop
                                Write-Verbose ("Constrained delegation on $($serviceAccount.SamAccountName) " +
                                    "to $($targets -join ', ')")
                            }
                            catch {
                                Write-Warning ("Could not set constrained delegation on " +
                                    "$($serviceAccount.SamAccountName): $($_.Exception.Message)")
                            }
                        }

                        Write-Verbose "Service account $($serviceAccount.SamAccountName) created successfully"
                        $script:ServiceAccountsCreated++
                    }
                    else {
                        Write-Host ("Would create service account: " +
                            "$($serviceAccount.SamAccountName)") -ForegroundColor Green
                    }
                }
                catch {
                    Write-Error ("Failed to create service account $($serviceAccount.SamAccountName): " +
                        "$($_.Exception.Message)")
                    $script:Errors += ("Service account creation error for $($serviceAccount.SamAccountName): " +
                        "$($_.Exception.Message)")
                }
            }

            Write-Progress -Activity "Creating Service Accounts" -Status "Complete" -PercentComplete 100 -Completed

            # Export passwords to file or SecretStore if accounts were created
            $passwordFile = $null
            $secretStoreResult = $null
            if ($script:PasswordExports.Count -gt 0 -and -not $WhatIfPreference) {
                Write-Verbose "Generated passwords for $($script:PasswordExports.Count) service accounts"

                # Handle SecretStore orchestration if requested
                if ($UseSecretStore) {
                    try {
                        $orchestrationParams = @{
                            PasswordData = $script:PasswordExports
                            VaultName = $VaultName
                            GlobalVault = $GlobalVault
                            CorrelationId = $correlationId
                        }

                        if ($VaultPassword) {
                            $orchestrationParams.VaultPassword = $VaultPassword
                        }

                        $secretStoreResult = Invoke-ADTestSecretStoreOrchestration @orchestrationParams

                        if ($secretStoreResult.Errors.Count -gt 0) {
                            Write-Warning ("SecretStore orchestration completed with errors: " +
                                "$($secretStoreResult.Errors -join '; ')")
                            # Fall back to file export
                            $exportPasswordDocumentationArgs2 = @{
                                PasswordData = $script:PasswordExports
                                FilePrefix   = "ServiceAccountPW"
                            }
                            $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs2
                            Write-Warning "Passwords exported to file as fallback: $passwordFile"
                        }
                        else {
                            Write-Verbose ("Successfully stored $($secretStoreResult.PasswordsStored) passwords " +
                                "in SecretStore vault: $VaultName")
                        }
                    }
                    catch {
                        Write-Warning "SecretStore orchestration failed: $($_.Exception.Message)"
                        # Fall back to file export
                        $exportPasswordDocumentationArgs3 = @{
                            PasswordData = $script:PasswordExports
                            FilePrefix   = "ServiceAccountPW"
                        }
                        $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs3
                        Write-Warning "Passwords exported to file as fallback: $passwordFile"
                    }
                }
                else {
                    # Export to file when not using SecretStore
                    $exportPasswordDocumentationArgs4 = @{
                        PasswordData = $script:PasswordExports
                        FilePrefix   = "ServiceAccountPW"
                    }
                    $passwordFile = Export-ADTestPasswordDocumentation @exportPasswordDocumentationArgs4
                    Write-Verbose "Service account passwords exported to: $passwordFile"
                }
            }

            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalAccounts = $totalAccounts
                CreatedAccounts = $script:ServiceAccountsCreated
                SkippedAccounts = $script:ServiceAccountsSkipped
                PasswordData = $script:PasswordExports
                PasswordFile = if ($passwordFile) { $passwordFile } else { $null }
                SecretStoreResult = if ($secretStoreResult) { $secretStoreResult } else { $null }
                UseSecretStore = $UseSecretStore
                VaultName = if ($UseSecretStore) { $VaultName } else { $null }
                Errors = $script:Errors
            }

            # Display summary or return results
            if ($PassThru) {
                return [PSCustomObject]$results
            } else {
                Write-TestMessage -Message "Service Account Creation Summary" -Type Success
                Write-Host "  Accounts Created: $($results.CreatedAccounts)" -ForegroundColor Green
                Write-Host "  Accounts Skipped: $($results.SkippedAccounts)" -ForegroundColor Yellow

                if ($results.PasswordData.Count -gt 0) {
                    Write-Host "  Passwords Generated: $($results.PasswordData.Count)" -ForegroundColor Cyan
                    Write-Host ("  INFO: Password data available in results object for external " +
                        "handling") -ForegroundColor Green
                }

                if ($results.Errors.Count -gt 0) {
                    Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                    $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
                }
            }

        } catch {
            Write-Error "Failed to create service accounts: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestServiceAccount - CorrelationId: $correlationId"
    }
}
