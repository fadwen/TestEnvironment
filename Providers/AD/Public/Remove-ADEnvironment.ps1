function Remove-ADEnvironment {
    <#
    .SYNOPSIS
        Safely removes all AD test data created by the ADTestEnvironment module

    .DESCRIPTION
        Performs a complete cleanup of test data including users, devices, security groups,
        and optionally OUs. Includes safety checks and progress reporting.

    .PARAMETER RemoveOUs
        Also removes the test OU structure (WARNING: This is destructive)

    .PARAMETER VaultName
        Name of the SecretStore vault to remove. Defaults to "ADTestEnvironment"

    .PARAMETER Force
        Bypasses confirmation prompts (use with caution)

    .PARAMETER ResetSecretStore
        Also reset the global SecretStore configuration to defaults.
        WARNING: This will affect ALL SecretStore vaults on the system.
        Use with caution if you have other vaults configured.

    .PARAMETER GlobalVault
        Create/remove vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges.

    .PARAMETER PassThru
        Returns detailed results object (default: summary only)

    .PARAMETER WhatIf
        Shows what would be removed without making changes

    .EXAMPLE
        Remove-ADEnvironment -WhatIf
        Shows what would be removed without making changes

    .EXAMPLE
        Remove-ADEnvironment -RemoveOUs -Force
        Removes all test data including OUs and SecretStore vault without confirmation

    .EXAMPLE
        Remove-ADEnvironment -VaultName "CustomVault"
        Removes test data and a custom named vault

    .EXAMPLE
        Remove-ADEnvironment -ResetSecretStore -Force
        Removes test data, vault, AND resets SecretStore configuration without prompts

    .EXAMPLE
        Remove-ADEnvironment -GlobalVault -Force
        Removes test data and a global vault (requires admin privileges)

    .OUTPUTS
        Hashtable with removal results and statistics

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2025-08-05
        
        WARNING: This function is destructive. Always test with -WhatIf first.
        
        SECRETSTORE CLEANUP:
        - Automatically removes SecretStore vaults created during environment setup
        - All stored passwords/secrets will be permanently deleted
        - Vault removal is a management operation that doesn't require the vault password
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$RemoveOUs,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [switch]$Force,
        [switch]$PassThru,
        
        [Parameter()]
        [switch]$ResetSecretStore,
        
        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Remove-ADEnvironment - CorrelationId: $correlationId"
        
        # Get domain information
        $domain = Get-ADTestDomain
        
        # Safety check - confirm this is a test environment.
        #
        # Skipped under -WhatIf: a preview changes nothing, so demanding that someone type
        # CONFIRM before being shown what would happen is backwards, and it made -WhatIf
        # unusable from anything non-interactive.
        if (-not $Force -and -not $WhatIfPreference) {
            Write-Warning "This will permanently delete all test data from Active Directory."
            Write-Warning "Domain: $($domain.DNSName)"
            if ($RemoveOUs) {
                Write-Warning "OU REMOVAL ENABLED: This will also delete the entire test OU structure!"
            }

            $confirmation = Read-Host "Type 'CONFIRM' to proceed with deletion"
            if ($confirmation -ne 'CONFIRM') {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                return @{ Cancelled = $true }
            }
        }

        # One confirmation covers the whole run.
        #
        # This is what the guards below used to express as "$Force -or $manuallyConfirmed -or
        # ShouldProcess(...)", and that short-circuit was a serious bug: with -Force the first
        # operand was true, ShouldProcess was never consulted, and -WhatIf was ignored -
        # "Remove-ADEnvironment -RemoveOUs -Force -WhatIf" really deleted the directory.
        #
        # Suppressing ConfirmPreference instead keeps the intent (ask once, not once per
        # object) while leaving ShouldProcess as the single gate, so -WhatIf always wins and
        # emits the standard "What if:" line for every object.
        $ConfirmPreference = 'None'

        # Counters
        $script:UsersRemoved = 0
        $script:DevicesRemoved = 0
        $script:GroupsRemoved = 0
        $script:OUsRemoved = 0
        $script:PoliciesRemoved = 0
        $script:GroupPoliciesRemoved = 0
        $script:VaultsRemoved = 0
        $script:SecretsRemoved = 0
        $script:Errors = @()
    }

    process {
        try {
            Write-TestMessage -Message "Removing Active Directory Test Environment" -Type Header

            # Anything of ours that is no longer where we put it. The sweeps below all search the
            # seeded container, so an object moved out of it becomes unmanaged - created by this
            # module, invisible to its teardown, and left behind for somebody to find by hand.
            # That is not hypothetical: a faulty run once left 296 seeded accounts in the default
            # Users container, and clearing them took a query written by hand.
            #
            # The tag makes this safe to do domain-wide. Only objects carrying it are named, and
            # they are only ever reported here - removal still happens in the typed sweeps below,
            # which know how to deal with each class.
            $strayFilter = "(adminDescription=$((Get-ADTestSeedMarker).Tag))"
            $strays = @(
                Get-ADObject -LDAPFilter $strayFilter -SearchBase $domain.DomainDN -ErrorAction SilentlyContinue |
                    Where-Object { $_.DistinguishedName -notlike "*OU=$($script:ADTestRootName),$($domain.DomainDN)" }
            )

            if ($strays.Count -gt 0) {
                Write-Warning ("$($strays.Count) seeded object(s) carry the seed tag but sit outside " +
                    "OU=$($script:ADTestRootName). They were created by this module and moved since. " +
                    'Listed below; remove them by hand or move them back and re-run.')
                foreach ($stray in $strays) {
                    Write-Warning "  $($stray.ObjectClass): $($stray.DistinguishedName)"
                }
            }

            # Step 1: Remove Test Users
            Write-TestMessage -Message "Removing test users..." -Type Info
            try {
                # Remove all users from TestData OU structure (excluding built-in accounts)
                $searchBase = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testUsers = @(Get-ADUser -Filter '*' -SearchBase $searchBase -Properties adminDescription -ErrorAction SilentlyContinue |
                    Select-ADTestOwnedObject -Kind user)
                
                foreach ($user in $testUsers) {
                    if ($PSCmdlet.ShouldProcess($user.Name, "Remove AD User")) {
                        try {
                            Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed user: $($user.Name)"
                            $script:UsersRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove user $($user.Name): $($_.Exception.Message)"
                            $script:Errors += "User removal error: $($user.Name)"
                        }
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test users found (TestData OU may not exist)"
                } else {
                    Write-Warning "Error searching for test users: $($_.Exception.Message)"
                }
                $script:Errors += "User search error: $($_.Exception.Message)"
            }
            
            # Step 2: Remove Test Devices
            Write-TestMessage -Message "Removing test devices..." -Type Info
            try {
                # Remove all devices from TestData OU structure
                $searchBase = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testDevices = @(Get-ADComputer -Filter '*' -SearchBase $searchBase -Properties adminDescription -ErrorAction SilentlyContinue |
                    Select-ADTestOwnedObject -Kind computer)
                
                foreach ($device in $testDevices) {
                    if ($PSCmdlet.ShouldProcess($device.Name, "Remove AD Computer")) {
                        try {
                            Remove-ADComputer -Identity $device.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed device: $($device.Name)"
                            $script:DevicesRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove device $($device.Name): $($_.Exception.Message)"
                            $script:Errors += "Device removal error: $($device.Name)"
                        }
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test devices found (TestData OU may not exist)"
                } else {
                    Write-Warning "Error searching for test devices: $($_.Exception.Message)"
                }
                $script:Errors += "Device search error: $($_.Exception.Message)"
            }
            
            # Step 3: Remove Test Service Accounts
            Write-TestMessage -Message "Removing test service accounts..." -Type Info
            try {
                # Remove all service accounts from ServiceAccounts OU
                $svcQuery = @{
                    Filter      = '*'
                    SearchBase  = "OU=ServiceAccounts,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                    ErrorAction = 'SilentlyContinue'
                    Properties  = 'adminDescription'
                }
                $testServiceAccounts = @(Get-ADUser @svcQuery | Select-ADTestOwnedObject -Kind 'service account')
                
                foreach ($serviceAccount in $testServiceAccounts) {
                    if ($PSCmdlet.ShouldProcess($serviceAccount.Name, "Remove AD Service Account")) {
                        try {
                            Remove-ADUser -Identity $serviceAccount.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed service account: $($serviceAccount.Name)"
                            $script:UsersRemoved++
                        }
                        catch {
                            Write-Warning ("Failed to remove service account $($serviceAccount.Name): " +
                                "$($_.Exception.Message)")
                            $script:Errors += "Service account removal error: $($serviceAccount.Name)"
                        }
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test service accounts found (ServiceAccounts OU may not exist)"
                } else {
                    Write-Warning "Error searching for test service accounts: $($_.Exception.Message)"
                }
                $script:Errors += "Service account search error: $($_.Exception.Message)"
            }
            
            # Step 4: Remove Test Security Groups
            Write-TestMessage -Message "Removing test security groups..." -Type Info
            try {
                # Searched across the whole of OU=TestData, not just OU=Groups.
                #
                # The users sweep above already works this way; groups did not, so any group
                # living outside OU=Groups survived a teardown that was not given -RemoveOUs.
                # The edge case groups are the concrete case - they sit under OU=EdgeCases -
                # but it applies to anything placed elsewhere in the tree later.
                $searchBase = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testGroups = @(Get-ADGroup -Filter '*' -SearchBase $searchBase -Properties adminDescription -ErrorAction SilentlyContinue |
                    Select-ADTestOwnedObject -Kind group)
                
                foreach ($group in $testGroups) {
                    if ($PSCmdlet.ShouldProcess($group.Name, "Remove AD Group")) {
                        try {
                            Remove-ADGroup -Identity $group.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed group: $($group.Name)"
                            $script:GroupsRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove group $($group.Name): $($_.Exception.Message)"
                            $script:Errors += "Group removal error: $($group.Name)"
                        }
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test groups found (Groups OU may not exist)"
                } else {
                    Write-Warning "Error searching for test groups: $($_.Exception.Message)"
                }
                $script:Errors += "Group search error: $($_.Exception.Message)"
            }
            
            # Step 4b: Remove edge case password settings objects
            #
            # A password settings object lives in CN=Password Settings Container,CN=System,
            # not under OU=TestData, so it is the one thing New-ADTestEdgeCase creates that
            # the recursive OU delete cannot reach. Removed by name prefix rather than by
            # location, and only ones this module creates.
            Write-TestMessage -Message "Removing edge case password settings objects..." -Type Info
            try {
                $testPolicies = @(Get-ADFineGrainedPasswordPolicy -Filter ("Name -like " +
                    "'EdgeCase*'") -ErrorAction SilentlyContinue)

                foreach ($policy in $testPolicies) {
                    if ($PSCmdlet.ShouldProcess($policy.Name, "Remove AD Fine-Grained Password Policy")) {
                        try {
                            Remove-ADFineGrainedPasswordPolicy -Identity $policy.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed password settings object: $($policy.Name)"
                            $script:PoliciesRemoved++
                        }
                        catch {
                            Write-Warning ("Failed to remove password policy $($policy.Name): " +
                                "$($_.Exception.Message)")
                            $script:Errors += "Password policy removal error: $($policy.Name)"
                        }
                    }
                }
            }
            catch {
                Write-Verbose "No edge case password settings objects found: $($_.Exception.Message)"
            }

            # The companion deny-logon policy lives in CN=Policies,CN=System, so like the
            # password settings objects above it is outside OU=TestData and a recursive OU
            # delete cannot reach it. Removed before the OUs so the link is unwound while
            # its target still exists, rather than leaving an orphaned policy behind.
            #
            # Matched on the marker in the comment as well as the name: deleting a GPO is
            # not recoverable, and a real policy that happened to share the name must not
            # be removed by a test teardown.
            Write-TestMessage -Message "Removing test Group Policy objects..." -Type Info
            try {
                Import-Module GroupPolicy -ErrorAction Stop -Verbose:$false

                $policy = Get-ADTestPolicySetting -DomainDN $domain.DomainDN
                $testGpo = Get-GPO -Name $policy.Name -ErrorAction SilentlyContinue

                if (-not $testGpo) {
                    Write-Verbose "No test Group Policy found (already clean)"
                }
                elseif ([string]$testGpo.Description -notlike "*$($policy.Marker)*") {
                    $skipMsg = "A GPO named '$($policy.Name)' exists but does not carry " +
                               'this module marker, so it was left alone'
                    Write-Warning $skipMsg
                    $script:Errors += $skipMsg
                }
                elseif ($PSCmdlet.ShouldProcess($policy.Name, 'Remove Group Policy object')) {
                    # Unlink first where the target still exists. Remove-GPO drops the links
                    # too, but doing it explicitly keeps the intent readable and survives a
                    # partially removed OU tree.
                    $inheritance = Get-GPInheritance -Target $policy.LinkTarget -ErrorAction SilentlyContinue
                    if ($inheritance -and @($inheritance.GpoLinks |
                            Where-Object { $_.DisplayName -eq $policy.Name }).Count -gt 0) {
                        Remove-GPLink -Guid $testGpo.Id -Target $policy.LinkTarget -ErrorAction SilentlyContinue |
                            Out-Null
                        Write-Verbose "Unlinked from $($policy.LinkTarget)"
                    }

                    Remove-GPO -Guid $testGpo.Id -ErrorAction Stop
                    $script:GroupPoliciesRemoved++
                    Write-Verbose "Removed Group Policy: $($policy.Name)"
                }
            }
            catch [System.IO.FileNotFoundException] {
                Write-Verbose "GroupPolicy module not available - skipping policy removal"
            }
            catch {
                Write-Warning "Failed to remove test Group Policy: $($_.Exception.Message)"
                $script:Errors += "Group Policy removal error: $($_.Exception.Message)"
            }

            # Step 5: Remove OUs (if requested)
            if ($RemoveOUs) {
                Write-TestMessage -Message "Removing test OU structure..." -Type Info
                
                if ($RemoveOUs) {
                    try {
                        # Remove OUs in reverse hierarchical order
                        $ouRemovalOrder = @(
                            "OU=Administrative,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Resource,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)", 
                            "OU=Device,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Location,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Role,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Department,OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Workstations,OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Servers,OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Printers,OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Mobile,OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=ServiceAccounts,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                        )
                        
                        # Add edge case OUs (dynamically discovered, deepest first).
                        #
                        # These hold the states New-ADTestEdgeCase creates. Two of them - a
                        # delegated access control entry and a planted orphaned SID - live in
                        # security descriptors rather than being objects, so they are only
                        # really gone once the OUs holding them are gone. Discovered rather
                        # than hardcoded so an edge case added later is still cleaned up, and
                        # sorted by depth so children are removed before their parents.
                        try {
                            $edgeCaseRoot = "OU=EdgeCases,OU=$($script:ADTestRootName),$($domain.DomainDN)"

                            # -SearchBase includes the base itself, so this returns the
                            # EdgeCases root along with its children and no separate entry
                            # for it is needed.
                            $edgeQuery = @{
                                Filter      = '*'
                                SearchBase  = $edgeCaseRoot
                                ErrorAction = 'SilentlyContinue'
                            }
                            $edgeOUs = @(Get-ADOrganizationalUnit @edgeQuery |
                                Sort-Object { ($_.DistinguishedName -split ',').Count } -Descending)

                            # Prepended in one go. Prepending inside a foreach reverses the
                            # sort - each item lands in front of the previous one - which put
                            # the root first and left every child entry to be logged as
                            # "already removed" after the recursive delete had taken it.
                            if ($edgeOUs.Count -gt 0) {
                                $ouRemovalOrder = @($edgeOUs.DistinguishedName) + $ouRemovalOrder
                            }
                        }
                        catch {
                            Write-Verbose "No edge case OUs found or error accessing them"
                        }

                        # Add department/user OUs (dynamically discovered)
                        try {
                            $userOUQuery = @{
                                Filter      = '*'
                                SearchBase  = "OU=Users,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                                ErrorAction = 'SilentlyContinue'
                            }
                            $userOUs = Get-ADOrganizationalUnit @userOUQuery
                            foreach ($userOU in $userOUs) {
                                if ($userOU.DistinguishedName -ne "OU=Users,OU=$($script:ADTestRootName),$($domain.DomainDN)") {
                                    $ouRemovalOrder = @($userOU.DistinguishedName) + $ouRemovalOrder
                                }
                            }
                        }
                        catch {
                            Write-Verbose "No user department OUs found or error accessing them"
                        }
                        
                        # Add the main structure OUs
                        $ouRemovalOrder += @(
                            "OU=Users,OU=$($script:ADTestRootName),$($domain.DomainDN)",
                            "OU=$($script:ADTestRootName),$($domain.DomainDN)"
                        )
                        
                        foreach ($ouPath in $ouRemovalOrder) {
                            if ($PSCmdlet.ShouldProcess($ouPath, "Remove AD Organizational Unit")) {
                                try {
                                    # Check if OU exists before trying to remove
                                    $ou = Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction SilentlyContinue

                                    # -Recursive deletes whatever is still inside, which would
                                    # undo the ownership check the sweeps above just applied: a
                                    # group this module refused to delete would die anyway when
                                    # its container went. Verified against a live domain, where
                                    # exactly that happened - teardown warned that it was
                                    # sparing an object and then removed it seconds later.
                                    #
                                    # So an organisational unit still holding anything untagged
                                    # is left standing, along with its contents. That makes
                                    # -RemoveOUs best-effort rather than absolute, which is the
                                    # correct trade: an incomplete teardown is recoverable and a
                                    # deleted production group is not.
                                    $foreign = @()
                                    if ($ou) {
                                        $foreign = @(
                                            Get-ADObject -Filter * -SearchBase $ouPath -Properties adminDescription -ErrorAction SilentlyContinue |
                                                Where-Object {
                                                    $_.DistinguishedName -ne $ouPath -and
                                                    $_.adminDescription -ne (Get-ADTestSeedMarker).Tag
                                                }
                                        )
                                    }

                                    if ($foreign.Count -gt 0) {
                                        Write-Warning ("Not removing $ouPath : it still holds $($foreign.Count) object(s) " +
                                            'this module cannot prove it created. Remove them or move them out, then re-run.')
                                        foreach ($item in $foreign) {
                                            Write-Warning "  $($item.ObjectClass): $($item.DistinguishedName)"
                                        }
                                        continue
                                    }

                                    if ($ou) {
                                        # Enable deletion by removing protection. -WhatIf:$false
                                        # is NOT used here on purpose: this whole branch is
                                        # already behind ShouldProcess, so under -WhatIf it
                                        # never runs and the protection flag is left alone.
                                        $setADOrganizationalUnitArgs1 = @{
                                            Identity                        = $ouPath
                                            ProtectedFromAccidentalDeletion = $false
                                            ErrorAction                     = 'SilentlyContinue'
                                        }
                                        Set-ADOrganizationalUnit @setADOrganizationalUnitArgs1
                                        Remove-ADOrganizationalUnit -Identity $ouPath -Recursive -Confirm:$false
                                        Write-Verbose "Removed OU: $ouPath"
                                        $script:OUsRemoved++
                                    }
                                }
                                catch {
                                    # Only warn for actual failures, not missing OUs
                                    if ($_.Exception.Message -notmatch "Directory object not found") {
                                        Write-Warning "Failed to remove OU $ouPath : $($_.Exception.Message)"
                                        $script:Errors += "OU removal error: $ouPath"
                                    }
                                    else {
                                        Write-Verbose "OU not found (already removed): $ouPath"
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        # Only warn for actual failures, not missing search bases
                        if ($_.Exception.Message -notmatch "Directory object not found") {
                            Write-Warning "Error during OU removal: $($_.Exception.Message)"
                            $script:Errors += "OU removal process error: $($_.Exception.Message)"
                        }
                        else {
                            Write-Verbose "OU structure not found (already clean): $($_.Exception.Message)"
                        }
                    }
                }
            }
            
            # Remove SecretStore vault if it exists
            try {
                Write-TestMessage -Message "Checking for SecretStore vault removal..." -Type Info
                
                # Same fix as the AD guards above. This one mattered doubly: with -Force the
                # short-circuit meant Remove-ADTestSecretVault was invoked for real under
                # -WhatIf, destroying stored secrets during what was meant to be a preview.
                if ($PSCmdlet.ShouldProcess("SecretStore Vault: $VaultName", "Remove Secret Vault")) {
                    $removeADTestSecretVaultArgs2 = @{
                        VaultName        = $VaultName
                        Force            = $Force
                        ResetSecretStore = $ResetSecretStore
                        GlobalVault      = $GlobalVault
                    }
                    $vaultResult = Remove-ADTestSecretVault @removeADTestSecretVaultArgs2
                    
                    if ($vaultResult.VaultRemoved) {
                        $script:VaultsRemoved++
                        $script:SecretsRemoved += $vaultResult.SecretsRemoved
                        Write-Host "  Removed SecretStore vault: $VaultName" -ForegroundColor Green
                        Write-Host "  Removed $($vaultResult.SecretsRemoved) stored secrets" -ForegroundColor Green
                        
                        if ($vaultResult.SecretStoreReset) {
                            Write-Host "  Reset SecretStore configuration to defaults" -ForegroundColor Green
                        }
                    }
                    elseif ($vaultResult.VaultExists -eq $false) {
                        Write-Host "  SecretStore vault '$VaultName' was not found" -ForegroundColor Yellow
                    }
                    
                    if ($vaultResult.Errors.Count -gt 0) {
                        $vaultResult.Errors | ForEach-Object { 
                            Write-Warning "Vault removal error: $_"
                            $script:Errors += "Vault removal: $_"
                        }
                    }
                }
            }
            catch {
                Write-Warning "Error during vault removal: $($_.Exception.Message)"
                $script:Errors += "Vault removal process error: $($_.Exception.Message)"
            }
            
            # Create summary
            $results = @{
                CorrelationId = $correlationId
                UsersRemoved = $script:UsersRemoved
                DevicesRemoved = $script:DevicesRemoved
                GroupsRemoved = $script:GroupsRemoved
                OUsRemoved = $script:OUsRemoved
                PoliciesRemoved = $script:PoliciesRemoved
                GroupPoliciesRemoved = $script:GroupPoliciesRemoved
                VaultsRemoved = $script:VaultsRemoved
                SecretsRemoved = $script:SecretsRemoved
                OUsRequested = $RemoveOUs
                Errors = $script:Errors
                TotalRemoved = $script:UsersRemoved + $script:DevicesRemoved +
                               $script:GroupsRemoved + $script:OUsRemoved +
                               $script:VaultsRemoved
            }
            
            # Display summary
            Write-TestMessage -Message "Test Environment Removal Summary" -Type Success
            Write-Host "  Users Removed: $($results.UsersRemoved)" -ForegroundColor Green
            Write-Host "  Devices Removed: $($results.DevicesRemoved)" -ForegroundColor Green
            Write-Host "  Groups Removed: $($results.GroupsRemoved)" -ForegroundColor Green
            if ($RemoveOUs) {
                Write-Host "  OUs Removed: $($results.OUsRemoved)" -ForegroundColor Green
            }
            if ($results.PoliciesRemoved -gt 0) {
                Write-Host ("  Password Settings Objects Removed: " +
                    "$($results.PoliciesRemoved)") -ForegroundColor Green
            }
            if ($results.GroupPoliciesRemoved -gt 0) {
                Write-Host ("  Group Policy Objects Removed: " +
                    "$($results.GroupPoliciesRemoved)") -ForegroundColor Green
            }
            if ($results.VaultsRemoved -gt 0) {
                Write-Host "  SecretStore Vaults Removed: $($results.VaultsRemoved)" -ForegroundColor Green
            }
            if ($results.SecretsRemoved -gt 0) {
                Write-Host "  Secrets Removed: $($results.SecretsRemoved)" -ForegroundColor Green
            }
            Write-Host "  Total Objects Removed: $($results.TotalRemoved)" -ForegroundColor Cyan
            
            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            else {
                Write-Host "  No errors encountered!" -ForegroundColor Green
            }
            
            # Return detailed results for programmatic access only
            if ($PassThru) {
                return [PSCustomObject]$results
            }
            # Store results in verbose output for troubleshooting
            Write-Verbose "Detailed results: $($results | ConvertTo-Json -Depth 3)"
            
        } catch {
            Write-Error "Failed to remove test environment: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Remove-ADEnvironment - CorrelationId: $correlationId"
    }
}
