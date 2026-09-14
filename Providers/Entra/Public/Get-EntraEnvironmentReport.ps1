function Get-EntraEnvironmentReport {
    <#
    .SYNOPSIS
        Reports what is currently seeded in the tenant, and how it is shaped

    .DESCRIPTION
        Reads the seeded environment back out of the tenant and reports it. It reads what is
        actually there rather than what the seed data says should be there, which is the only
        way the report can tell you that a step failed, that somebody deleted a group by
        hand, or that a dynamic group has not evaluated yet.

        Group membership is reported both directly and transitively, because the difference
        is the whole point of the nesting chain. A group that reports four direct members and
        ten transitive ones is working; if those numbers match, either the nesting failed or
        whatever produced the report only expanded one level.

        Licence assignment paths are resolved rather than counted. Graph reports an inherited
        licence and a directly-assigned one identically in assignedLicenses, and only
        licenseAssignmentStates distinguishes them - the inherited entry names the group in
        assignedByGroup. The report resolves that group id back to a name, because a report
        that hands you a bare GUID has made you do the interesting half of the work.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV. The file formats are written by the one writer every
        provider shares; CSV is a folder with one file per section. -Format is kept as an alias.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console. -Path is
        kept as an alias.

    .PARAMETER PassThru
        Returns the report object as well.

    .OUTPUTS
        EntraEnvironmentReport, the shape every provider returns, when -PassThru is supplied.

    .EXAMPLE
        PS> Get-EntraEnvironmentReport

        DESCRIPTION: Prints a summary of everything currently seeded
        OUTPUT: A per-type breakdown with membership and licence detail
        USE CASE: Confirming a seed worked, or seeing what is left after a partial teardown

    .EXAMPLE
        PS> Get-EntraEnvironmentReport -OutputFormat JSON -OutputPath .\lab.json

        DESCRIPTION: Writes the full report as JSON
        OUTPUT: The file, and nothing on the pipeline
        USE CASE: Diffing the environment between runs

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The console format exists to be read by a person at the console.')]
    [CmdletBinding()]
    [OutputType('EntraEnvironmentReport')]
    param(
        [Parameter()]
        [Alias('Format')]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [Alias('Path')]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
        throw "-OutputPath is required for the $OutputFormat format."
    }
    $marker = Get-EntraSeedMarker -Connection $connection

    Write-Verbose "Reading the seeded environment under '$($marker.Prefix)'"

    $users = @(Get-EntraSeededObject -Type Users -Connection $connection)
    $groups = @(Get-EntraSeededObject -Type Groups -Connection $connection)
    $devices = @(Get-EntraSeededObject -Type Devices -Connection $connection)
    $applications = @(Get-EntraSeededObject -Type Applications -Connection $connection)
    $principals = @(Get-EntraSeededObject -Type ServicePrincipals -Connection $connection)
    $locations = @(Get-EntraSeededObject -Type NamedLocations -Connection $connection)
    $policies = @(Get-EntraSeededObject -Type ConditionalAccessPolicies -Connection $connection)
    # Discovery raises a terminating error here rather than returning empty when it cannot tell,
    # because teardown has to distinguish the two. A report has no such stake, so it degrades to
    # a null count - which prints as blank rather than as a zero that would read as "none".
    $eligibilities = @()
    $eligibilityCount = $null
    $capability = $connection.Capabilities
    if ($capability -and $capability.Known -and -not $capability.EntraP2) {
        # Without P2 there can be none, and the read would be refused: zero, not unknown.
        $eligibilityCount = 0
    }
    else {
        try {
            $eligibilities = @(Get-EntraSeededObject -Type RoleEligibilities -Connection $connection -ErrorAction Stop)
            $eligibilityCount = $eligibilities.Count
        }
        catch {
            Write-Warning "Could not read the role eligibilities, so they are reported as unknown: $($_.Exception.Message)"
        }
    }

    # Counted three different ways on purpose, because the three disagree and the disagreement
    # is the finding. userType misses the guest that was converted to a member; the #EXT# marker
    # misses the one created locally with userType Guest; externalUserState sees only the
    # invitations nobody has redeemed. Any single number here is wrong.
    $externalByType = @($users | Where-Object { $_.userType -eq 'Guest' })
    $externalByUpn = @($users | Where-Object { $_.userPrincipalName -like '*#EXT#@*' })
    $externalPending = @($users | Where-Object { $_.externalUserState -eq 'PendingAcceptance' })

    # Measured, not assumed. The whole point of the eligibility layer is that roleAssignments
    # returns nothing for these roles while three principals can activate into them, and a
    # report that printed a hardcoded zero next to that claim would be asserting it rather than
    # showing it. If this is ever non-zero, somebody made a standing assignment by hand.
    $activeAssignments = @()
    $seededRoleIds = @(@(Get-EntraSeededObject -Type DirectoryRoles -Connection $connection).id)
    foreach ($roleId in $seededRoleIds) {
        try {
            $activeAssignments += @(Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                    -Path '/roleManagement/directory/roleAssignments' `
                    -Query @{ '$filter' = "roleDefinitionId eq '$roleId'"; '$select' = 'id,principalId,directoryScopeId' })
        }
        catch {
            Write-Verbose "Could not read active assignments for role $roleId : $($_.Exception.Message)"
        }
    }

    # Resolved once so licence paths can name the group rather than hand back a GUID.
    $groupNameById = @{}
    foreach ($group in $groups) { $groupNameById[$group.id] = $group.displayName }

    $skuNameById = @{}
    try {
        foreach ($sku in (Invoke-EntraRequest -Method GET -Path '/subscribedSkus' -Connection $connection).value) {
            $skuNameById[$sku.skuId] = $sku.skuPartNumber
        }
    }
    catch {
        Write-Warning "Could not read the tenant's SKUs, so licences will be reported by id: $($_.Exception.Message)"
    }

    # Managers and licence states are fetched in batches rather than two calls per user. At AD
    # parity that is the difference between a report that takes three minutes and one that
    # takes twenty seconds, and it is the same six hundred requests either way.
    Write-Verbose "Reading managers and licence states for $($users.Count) user(s)"

    $managerByUserId = @{}
    if ($users.Count -gt 0) {
        $managerRequests = foreach ($user in $users) {
            [PSCustomObject]@{ Reference = $user.id; Method = 'GET'; Url = "/users/$($user.id)/manager?`$select=displayName" }
        }
        foreach ($result in (Invoke-EntraBatch -Request @($managerRequests) -Connection $connection -Activity 'Reading managers')) {
            # A user with no manager answers 404 here. Three of the core users are like that
            # on purpose, so it is a value rather than a failure.
            if ($result.Success -and $result.Body) { $managerByUserId[$result.Reference] = $result.Body.displayName }
        }
    }

    $licenseStatesByUserId = @{}
    if ($users.Count -gt 0) {
        $licenceRequests = foreach ($user in $users) {
            [PSCustomObject]@{ Reference = $user.id; Method = 'GET'; Url = "/users/$($user.id)?`$select=licenseAssignmentStates" }
        }
        foreach ($result in (Invoke-EntraBatch -Request @($licenceRequests) -Connection $connection -Activity 'Reading licence states')) {
            if ($result.Success -and $result.Body) { $licenseStatesByUserId[$result.Reference] = @($result.Body.licenseAssignmentStates) }
        }
    }

    $userDetail = foreach ($user in $users) {
        $manager = $managerByUserId[$user.id]

        # Resolved rather than counted. Graph reports an inherited licence and a directly
        # assigned one identically in assignedLicenses; only licenseAssignmentStates
        # distinguishes them, and only by naming the group id in assignedByGroup.
        $licenseDetail = foreach ($state in @($licenseStatesByUserId[$user.id])) {
            if (-not $state) { continue }
            $skuName = if ($skuNameById.ContainsKey($state.skuId)) { $skuNameById[$state.skuId] } else { $state.skuId }
            $path = if ($state.assignedByGroup) {
                $viaName = if ($groupNameById.ContainsKey($state.assignedByGroup)) { $groupNameById[$state.assignedByGroup] } else { $state.assignedByGroup }
                "Inherited from $viaName"
            }
            else { 'Direct' }
            '{0} ({1})' -f $skuName, $path
        }

        [PSCustomObject]@{
            PSTypeName        = 'EntraReportUser'
            DisplayName       = $user.displayName
            UserPrincipalName = $user.userPrincipalName
            Enabled           = $user.accountEnabled
            Department        = $user.department
            UsageLocation     = $user.usageLocation
            Manager           = $manager
            Licenses          = @($licenseDetail)

            # All three, never one derived from the others. A caller that wants to know whether
            # this identity is external has to decide which question it is actually asking.
            UserType          = $user.userType
            ExternalUserState = $user.externalUserState
            IsExternalUpn     = [bool]($user.userPrincipalName -like '*#EXT#@*')
            SeedProof         = $user.SeedProof
        }
    }

    # Counted with $count rather than by paging every member. The difference between direct
    # and transitive membership is the whole point of the nesting, and at parity some groups
    # expand to nearly a hundred members - paging them all back just to measure the length is
    # a lot of traffic for a number Graph will return on its own.
    Write-Verbose "Counting membership for $($groups.Count) group(s)"

    $countMembership = {
        param($Relationship)
        $counts = @{}
        if ($groups.Count -eq 0) { return $counts }

        $requests = foreach ($group in $groups) {
            [PSCustomObject]@{
                Reference = $group.id
                Method    = 'GET'
                Url       = "/groups/$($group.id)/$Relationship/`$count"
                # Graph refuses a $count segment without this, and the header has to sit on
                # the inner request: the outer batch call's headers do not reach it.
                Headers   = @{ 'ConsistencyLevel' = 'eventual' }
            }
        }
        foreach ($result in (Invoke-EntraBatch -Request @($requests) -Connection $connection -Activity "Counting $Relationship")) {
            if ($result.Success) { $counts[$result.Reference] = [int]$result.Body }
        }
        return $counts
    }

    $directCounts = & $countMembership 'members'
    $transitiveCounts = & $countMembership 'transitiveMembers'

    $groupDetail = foreach ($group in $groups) {
        $direct = if ($directCounts.ContainsKey($group.id)) { $directCounts[$group.id] } else { 0 }
        $transitive = if ($transitiveCounts.ContainsKey($group.id)) { $transitiveCounts[$group.id] } else { 0 }

        [PSCustomObject]@{
            PSTypeName        = 'EntraReportGroup'
            DisplayName       = $group.displayName
            Kind              = if (@($group.groupTypes) -contains 'Unified') { 'Unified' } else { 'Security' }
            Membership        = if (@($group.groupTypes) -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }
            MembershipRule    = $group.membershipRule
            DirectMembers     = $direct
            TransitiveMembers = $transitive
            RoleAssignable    = [bool]$group.isAssignableToRole
            Licenses          = @($group.assignedLicenses | ForEach-Object {
                    if ($skuNameById.ContainsKey($_.skuId)) { $skuNameById[$_.skuId] } else { $_.skuId }
                })
            SeedProof         = $group.SeedProof
        }
    }

    $applicationDetail = foreach ($application in $applications) {
        $principal = $principals | Where-Object { $_.appId -eq $application.appId } | Select-Object -First 1
        $assignments = @()
        if ($principal) {
            try {
                $assignments = @((Invoke-EntraRequest -Method GET -Path "/servicePrincipals/$($principal.id)/appRoleAssignedTo" `
                            -Connection $connection -Paginate) | ForEach-Object { $_.principalDisplayName })
            }
            catch {
                Write-Warning "Could not read assignments for '$($application.displayName)': $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            PSTypeName          = 'EntraReportApplication'
            DisplayName         = $application.displayName
            AppId               = $application.appId
            HasServicePrincipal = [bool]$principal
            Hidden              = (@($application.tags) -contains 'HideApp')
            Assignments         = $assignments
            AssignmentCount     = $assignments.Count
            SeedProof           = $application.SeedProof
        }
    }

    $sections = [ordered]@{
        Users             = @($userDetail)
        Groups            = @($groupDetail)
        Applications      = @($applicationDetail)
        Devices           = @($devices | ForEach-Object {
                [PSCustomObject]@{
                    PSTypeName      = 'EntraReportDevice'
                    DisplayName     = $_.displayName
                    OperatingSystem = $_.operatingSystem
                    IsCompliant     = $_.isCompliant
                    IsManaged       = $_.isManaged
                    Enabled         = $_.accountEnabled
                    TrustType       = $_.trustType
                }
            })
        NamedLocations    = @($locations | ForEach-Object {
                [PSCustomObject]@{
                    PSTypeName  = 'EntraReportNamedLocation'
                    DisplayName = $_.displayName
                    Type        = ($_.'@odata.type' -replace '#microsoft.graph.', '')
                }
            })
        Policies          = @($policies | ForEach-Object {
                [PSCustomObject]@{
                    PSTypeName    = 'EntraReportPolicy'
                    DisplayName   = $_.displayName
                    State         = $_.state
                    GrantControls = @($_.grantControls.builtInControls)
                    Operator      = $_.grantControls.operator
                }
            })
        RoleEligibilities = @($eligibilities | ForEach-Object {
                [PSCustomObject]@{
                    PSTypeName  = 'EntraReportRoleEligibility'
                    Role        = $_.displayName
                    PrincipalId = $_.principalId
                    Scope       = $_.directoryScopeId

                    # Spelled out rather than left for the reader to infer from the scope string.
                    # A directory-wide eligibility and one confined to an administrative unit
                    # look nearly identical in the portal and are not remotely the same grant.
                    ScopeKind   = if ($_.directoryScopeId -eq '/') { 'Directory' } else { 'AdministrativeUnit' }
                    Status      = $_.status
                }
            })
    }
    $report = New-TestEnvironmentReport -Provider 'Entra' -Target $connection.TenantId -TypeName 'EntraEnvironmentReport' -Section $sections `
        -Property ([ordered]@{
            TenantId                = $connection.TenantId
            TenantName              = $connection.TenantName
            Prefix                  = $marker.Prefix
            UpnSuffix               = $marker.UpnSuffix
            ServicePrincipals       = $principals.Count
            GuestsByUserType        = $externalByType.Count
            GuestsByExternalUpn     = $externalByUpn.Count
            GuestsPendingAcceptance = $externalPending.Count
            # $null when the tenant refused the read, which is "unknown" and not zero.
            RoleEligibilityCount    = $eligibilityCount
            RoleAssignments         = $activeAssignments.Count
        })

    if ($OutputFormat -eq 'Console') {
        Write-TestMessage -Message "Entra test environment in $($report.TenantName) ($($report.TenantId))" -Type Header
        Write-Host "Prefix $($report.Prefix) on $($report.UpnSuffix)"
        Write-Host ''
        foreach ($property in $report.Counts.PSObject.Properties) {
            Write-Host ('  {0,-26} {1}' -f $property.Name, $property.Value)
        }
        foreach ($name in 'ServicePrincipals', 'GuestsByUserType', 'GuestsByExternalUpn', 'GuestsPendingAcceptance', 'RoleAssignments') {
            Write-Host ('  {0,-26} {1}' -f $name, $report.$name)
        }
        $eligible = if ($null -eq $report.RoleEligibilityCount) { 'unknown' } else { $report.RoleEligibilityCount }
        Write-Host ('  {0,-26} {1}' -f 'RoleEligibilities', $eligible)
        Write-Host ''
        Write-Host 'Users'
        foreach ($u in $report.Users) {
            Write-Host ('  {0,-40} enabled={1,-5} manager={2}' -f $u.DisplayName, $u.Enabled, $(if ($u.Manager) { $u.Manager } else { '(none)' }))
            foreach ($licence in $u.Licenses) { Write-Host "      licence: $licence" }
        }
        Write-Host ''
        Write-Host 'Groups'
        foreach ($g in $report.Groups) {
            Write-Host ('  {0,-40} {1,-9} direct={2,-3} transitive={3,-3}{4}' -f
                $g.DisplayName, $g.Membership, $g.DirectMembers, $g.TransitiveMembers,
                $(if ($g.Licenses) { " licences=$($g.Licenses -join ',')" } else { '' }))
        }
        Write-Host ''
        Write-Host 'Applications'
        foreach ($a in $report.Applications) {
            Write-Host ('  {0,-40} sp={1,-5} assignments={2}' -f $a.DisplayName, $a.HasServicePrincipal, $a.AssignmentCount)
        }
        Write-Host ''
        Write-Host 'Conditional Access policies'
        foreach ($p in $report.Policies) {
            Write-Host ('  {0,-46} {1}' -f $p.DisplayName, $p.State)
        }
    }
    else {
        Export-TestEnvironmentReport -Report $report -OutputFormat $OutputFormat -OutputPath $OutputPath `
            -FilePrefix 'EntraLab' -Title 'Entra Test Environment Report' `
            -Note @("Tenant $($report.TenantName) ($($report.TenantId))", "Prefix $($report.Prefix) on $($report.UpnSuffix)")
    }

    if ($PassThru) { return $report }
}
