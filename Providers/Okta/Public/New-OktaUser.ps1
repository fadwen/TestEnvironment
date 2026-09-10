function New-OktaUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Okta users from Data\OktaUsers.csv
    #>

    # The justification has to be one string constant: PSScriptAnalyzer rejects a concatenation
    # in a suppression attribute, and the error it gives says nothing about which one.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Deliberately weak shared lab password; -AccountPassword overrides it.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$UserCount = 8,

        [Parameter()]
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$SkipLifecycleStates,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    if (-not $AccountPassword) {
        $AccountPassword = ConvertTo-SecureString -String 'Okta-Lab-Passw0rd!2026' -AsPlainText -Force
    }
    $plainPassword = ConvertFrom-TestSecureString -SecureString $AccountPassword

    $csvPath = Join-Path -Path (Get-OktaDataPath) -ChildPath 'OktaUsers.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8 | Select-Object -First $UserCount)

    $result = [PSCustomObject]@{
        TotalUsers   = $rows.Count
        CreatedUsers = 0
        UpdatedUsers = 0
        Users        = @()
        Errors       = @()
    }

    # Manager is a display name and managerId a login, so the whole file has to be in hand
    # before the first user is built, not just the first $UserCount rows.
    $allRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $displayNameByLogin = @{}
    foreach ($row in $allRows) { $displayNameByLogin[$row.LoginPrefix] = $row.DisplayName }

    # Resolved once. A user's type can only be set at creation, so a row naming a type that
    # does not exist is worth failing loudly on rather than silently creating a default user.
    $userTypeIdByKey = @{}
    if (@($rows | Where-Object { $_.PSObject.Properties['OktaUserType'] -and $_.OktaUserType })) {
        foreach ($type in (Invoke-OktaRequest -Method GET -Path '/api/v1/meta/types/user')) {
            $userTypeIdByKey[$type.name] = $type.id
        }
    }

    $created = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $login = '{0}@{1}' -f $row.LoginPrefix, $connection.EmailDomain

        $userProfile = [ordered]@{
            login             = $login
            email             = $login
            firstName         = $row.FirstName
            lastName          = $row.LastName
            displayName       = $row.DisplayName
            nickName          = $row.NickName
            title             = $row.Title
            userType          = $row.UserType
            department        = $row.Department
            division          = $row.Division
            organization      = $row.Organization
            costCenter        = $row.CostCenter
            employeeNumber    = $row.EmployeeNumber
            mobilePhone       = $row.MobilePhone
            primaryPhone      = $row.PrimaryPhone
            streetAddress     = $row.StreetAddress
            city              = $row.City
            state             = $row.State
            zipCode           = $row.ZipCode
            countryCode       = $row.CountryCode
            preferredLanguage = $row.PreferredLanguage
            locale            = $row.Locale
            timezone          = $row.Timezone

            labSeedTag        = $connection.SeedTag
            labBadgeId        = $row.LabBadgeId
            labClearanceLevel = $row.LabClearanceLevel
            labIsContractor   = [bool]::Parse($row.LabIsContractor)
            labCostCenterOwner = $row.LabCostCenterOwner
        }

        if ($row.MiddleName)      { $userProfile.middleName = $row.MiddleName }
        if ($row.HonorificPrefix) { $userProfile.honorificPrefix = $row.HonorificPrefix }

        if ($row.ManagerLoginPrefix) {
            $userProfile.managerId = '{0}@{1}' -f $row.ManagerLoginPrefix, $connection.EmailDomain
            $userProfile.manager   = $displayNameByLogin[$row.ManagerLoginPrefix]
        }

        # Compared against empty string rather than tested for truth. A risk score of zero is
        # a legitimate value and falsy in PowerShell, and dropping it silently is exactly the
        # bug this attribute exists to expose.
        if ($row.LabRiskScore -ne '') { $userProfile.labRiskScore = [int]$row.LabRiskScore }
        if ($row.LabContractEndDate)  { $userProfile.labContractEndDate = $row.LabContractEndDate }

        $entitlements = @($row.LabEntitlements -split ';' | Where-Object { $_ })
        if ($entitlements.Count -gt 0) { $userProfile.labEntitlements = $entitlements }

        # Attributes that live only on the Contractor type's schema. Sending them to a default
        # user is a 400, so they follow the type rather than being set unconditionally.
        if ($row.PSObject.Properties['OktaUserType'] -and $row.OktaUserType) {
            if ($row.LabAgencyName)    { $userProfile.labAgencyName = $row.LabAgencyName }
            if ($row.LabPurchaseOrder) { $userProfile.labPurchaseOrder = $row.LabPurchaseOrder }
        }

        $lifecycle = if ($SkipLifecycleStates) { 'Active' } else { $row.LifecycleState }

        if (-not $PSCmdlet.ShouldProcess($login, "Create Okta user ($lifecycle)")) { continue }

        try {
            $existing = $null
            try {
                $existing = Invoke-OktaRequest -Method GET `
                    -Path "/api/v1/users/$([uri]::EscapeDataString($login))"
            }
            catch {
                Write-Verbose "No existing user for $login; it will be created."
            }

            if ($existing) {
                # A partial profile update. Okta merges rather than replaces here, which is
                # what makes a re-run after a half-finished seed safe.
                $user = Invoke-OktaRequest -Method POST -Path "/api/v1/users/$($existing.id)" `
                    -Body @{ profile = $userProfile }
                $result.UpdatedUsers++
                Write-Verbose "Updated $login"
            }
            else {
                $activate = ($lifecycle -ne 'Staged')
                $body = @{
                    profile     = $userProfile
                    credentials = @{ password = @{ value = $plainPassword } }
                }

                if ($row.PSObject.Properties['OktaUserType'] -and $row.OktaUserType) {
                    $typeName = Get-OktaUserTypeName -Prefix $connection.Prefix -UserTypeKey $row.OktaUserType
                    if (-not $userTypeIdByKey.ContainsKey($typeName)) {
                        throw ("User type '$typeName' does not exist. Run New-OktaUserType " +
                            'before creating users that belong to it.')
                    }
                    $body.type = @{ id = $userTypeIdByKey[$typeName] }
                }

                $user = Invoke-OktaRequest -Method POST -Path '/api/v1/users' `
                    -Query @{ activate = $activate.ToString().ToLowerInvariant() } -Body $body
                $result.CreatedUsers++
                Write-Verbose "Created $login ($lifecycle)"
            }

            if ($lifecycle -eq 'Suspended' -and $user.status -ne 'SUSPENDED') {
                $null = Invoke-OktaRequest -Method POST `
                    -Path "/api/v1/users/$($user.id)/lifecycle/suspend"
                $user.status = 'SUSPENDED'
            }

            $created.Add([PSCustomObject]@{
                Id          = $user.id
                Login       = $login
                DisplayName = $row.DisplayName
                Status      = $user.status
                Groups      = @($row.Groups -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create $login`: $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Users = $created.ToArray()

    Write-Verbose ("Users: $($result.CreatedUsers) created, $($result.UpdatedUsers) updated, " +
        "$($result.Errors.Count) failed")

    if ($PassThru) { return $result }
}
