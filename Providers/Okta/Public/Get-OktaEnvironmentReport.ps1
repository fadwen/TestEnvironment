function Get-OktaEnvironmentReport {
    <#
    .SYNOPSIS
        Reports on what this module has created in the connected tenant

    .DESCRIPTION
        Reads back the seeded users, groups, memberships, group rules, custom schema
        attributes and service app, and renders them.

        The report is the fastest way to answer the two questions that come up constantly with
        a licence-capped tenant: how many user slots are left, and did the group rules
        actually populate anything. Both are shown first for that reason.

        Memberships are read per group rather than per user, because Okta's group membership
        endpoint is authoritative and a user's own record does not list its groups.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV. CSV writes one file per section, since users, groups
        and rules have nothing in common to flatten into a single table. The file formats are
        written by the one writer every provider shares.

    .PARAMETER OutputPath
        Destination file for JSON and HTML, or destination folder for CSV. Required for
        anything other than Console.

    .PARAMETER PassThru
        Return the report object as well as rendering it

    .OUTPUTS
        PSCustomObject describing the environment, when -PassThru is used

    .EXAMPLE
        Get-OktaEnvironmentReport
        Prints a summary to the console

    .EXAMPLE
        Get-OktaEnvironmentReport -OutputFormat HTML -OutputPath .\okta-lab.html

    .EXAMPLE
        Get-OktaEnvironmentReport -OutputFormat CSV -OutputPath .\reports\
        Writes one OktaLab<Section>.csv per section: OktaLabUsers.csv, OktaLabGroups.csv,
        OktaLabGroupRules.csv and so on

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        CSV export is written as UTF-8 explicitly. Windows PowerShell's Export-Csv defaults to
        ASCII and would replace every accented character in the seeded names with a question
        mark, which is the exact data loss those names exist to expose.

    .LINK
        New-OktaEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console rendering is one of the supported output formats.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $headroom = Get-OktaUserHeadroom -ActiveUserLimit $connection.ActiveUserLimit
    $users = @(Get-OktaSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
    $groups = @(Get-OktaSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)

    $rulePrefix = '{0}-Rule-' -f $connection.Prefix
    $rules = @(Invoke-OktaRequest -Method GET -Path '/api/v1/groups/rules' -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith($rulePrefix, [StringComparison]::OrdinalIgnoreCase) })

    $apps = @(Get-OktaSeededApp -Prefix $connection.Prefix `
        -EmailDomain $connection.EmailDomain -IncludeServiceApp)

    # Every user type, not just the default. Reading only the default schema is the exact
    # mistake the second user type exists to expose, so the report must not make it.
    $userTypes = @(Invoke-OktaRequest -Method GET -Path '/api/v1/meta/types/user')
    $ownedTypes = @($userTypes | Where-Object {
        $_.name -and $_.name.StartsWith((Get-OktaUserTypeName -Prefix $connection.Prefix -UserTypeKey ''),
            [StringComparison]::OrdinalIgnoreCase)
    })

    $customAttributes = foreach ($type in $userTypes) {
        $schemaPath = '/api/v1/meta/schemas/user/default'
        if (-not $type.default -and $type._links -and $type._links.schema) {
            $schemaPath = ([uri]$type._links.schema.href).AbsolutePath
        }

        $schema = $null
        try { $schema = Invoke-OktaRequest -Method GET -Path $schemaPath }
        catch { Write-Verbose "Could not read schema for '$($type.name)': $($_.Exception.Message)" }

        if ($schema -and $schema.definitions.custom.properties) {
            $schema.definitions.custom.properties.PSObject.Properties |
                Where-Object { $_.Name -like 'lab*' } |
                ForEach-Object {
                    [PSCustomObject]@{
                        UserType = $type.name
                        Name     = $_.Name
                        Title    = $_.Value.title
                        Type     = $_.Value.type
                    }
                }
        }
    }

    $zones = @(Invoke-OktaRequest -Method GET -Path '/api/v1/zones' -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    # There is no "all policies" listing; the endpoint requires a type.
    $policies = @(foreach ($policyType in @('OKTA_SIGN_ON', 'PASSWORD')) {
        Invoke-OktaRequest -Method GET -Path '/api/v1/policies' `
            -Query @{ type = $policyType; limit = 200 } -Paginate |
            Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
                [StringComparison]::OrdinalIgnoreCase) }
    })

    $origins = @(Invoke-OktaRequest -Method GET -Path '/api/v1/trustedOrigins' `
        -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    $hooks = @(Invoke-OktaRequest -Method GET -Path '/api/v1/eventHooks' `
        -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    $linkedObjects = @(Invoke-OktaRequest -Method GET -Path '/api/v1/meta/schemas/user/linkedObjects')

    $userReport = foreach ($user in $users) {
        [PSCustomObject]@{
            Login      = $user.profile.login
            Name       = $user.profile.displayName
            Status     = $user.status
            Title      = $user.profile.title
            Department = $user.profile.department
            Manager    = $user.profile.manager
            Clearance  = $user.profile.labClearanceLevel
            Contractor = $user.profile.labIsContractor
            RiskScore  = $user.profile.labRiskScore
        }
    }

    $groupReport = foreach ($group in $groups) {
        # Wrapped for the same reason the app assignments are: a permission problem or a rate
        # limit on ONE group should cost you that group's member count, not the whole report.
        $members = @()
        try {
            $members = @(Invoke-OktaRequest -Method GET -Path "/api/v1/groups/$($group.id)/users" `
                -Query @{ limit = 200 } -Paginate)
        }
        catch {
            Write-Warning ("Could not read members of '$($group.profile.name)': " +
                "$($_.Exception.Message). Its count is reported as zero.")
        }

        [PSCustomObject]@{
            Name        = $group.profile.name
            Description = $group.profile.description
            MemberCount = $members.Count
            Members     = @($members | ForEach-Object { $_.profile.login })
        }
    }

    # Assignments are read per app rather than per user, because Okta's app-user endpoint is
    # authoritative and a user's own record does not list the apps they can reach. The scope
    # field is what distinguishes a direct assignment from a group-derived one, and keeping
    # both counts separate is the whole point: an access review that reports only the total
    # cannot tell you who would lose access if a group were unassigned.
    $appReport = foreach ($app in $apps) {
        $assignedGroups = @()
        $assignedUsers = @()
        try {
            $assignedGroups = @(Invoke-OktaRequest -Method GET `
                -Path "/api/v1/apps/$($app.id)/groups" -Query @{ limit = 200 } -Paginate)
            $assignedUsers = @(Invoke-OktaRequest -Method GET `
                -Path "/api/v1/apps/$($app.id)/users" -Query @{ limit = 200 } -Paginate)
        }
        catch {
            Write-Verbose "Could not read assignments for '$($app.label)': $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            Label       = $app.label
            Id          = $app.id
            Status      = $app.status
            SignOnMode  = $app.signOnMode
            GroupCount  = $assignedGroups.Count
            UserCount   = $assignedUsers.Count
            DirectUsers = @($assignedUsers | Where-Object { $_.scope -eq 'USER' } |
                ForEach-Object { $_.credentials.userName })
        }
    }

    $ruleReport = foreach ($rule in $rules) {
        [PSCustomObject]@{
            Name       = $rule.name
            Status     = $rule.status
            Expression = $rule.conditions.expression.value
            TargetIds  = @($rule.actions.assignUserToGroups.groupIds)
        }
    }

    $sections = [ordered]@{
        Users            = @($userReport)
        Groups           = @($groupReport)
        GroupRules       = @($ruleReport)
        CustomAttributes = @($customAttributes)
        Apps             = @($appReport)
        UserTypes        = @($ownedTypes | ForEach-Object {
            [PSCustomObject]@{ Name = $_.name; DisplayName = $_.displayName; Id = $_.id }
        })
        NetworkZones     = @($zones | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.name
                Usage    = $_.usage
                Status   = $_.status
                Gateways = @($_.gateways | ForEach-Object { $_.value })
            }
        })
        Policies         = @($policies | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.name
                Type     = $_.type
                Status   = $_.status
                Priority = $_.priority
            }
        })
        TrustedOrigins   = @($origins | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.name
                Origin = $_.origin
                Scopes = @($_.scopes | ForEach-Object { $_.type })
            }
        })
        EventHooks       = @($hooks | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.name
                Status = $_.status
                Uri    = $_.channel.config.uri
                Events = @($_.events.items)
            }
        })
        LinkedObjects    = @($linkedObjects | ForEach-Object {
            [PSCustomObject]@{ Primary = $_.primary.name; Associated = $_.associated.name }
        })
    }

    $report = New-TestEnvironmentReport -Provider 'Okta' -Target $connection.OrgUrl -TypeName 'OktaEnvironmentReport' -Section $sections `
        -Property ([ordered]@{
            GeneratedUtc = [DateTime]::UtcNow.ToString('o')
            OrgUrl       = $connection.OrgUrl
            Prefix       = $connection.Prefix
            AuthType     = $connection.AuthType
            Licence      = [PSCustomObject]@{
                ActiveUserLimit = $headroom.Limit
                InUse           = $headroom.InUse
                Available       = $headroom.Available
            }
        })

    switch ($OutputFormat) {
        'Console' {
            Write-TestMessage -Message "Okta Test Environment - $($report.OrgUrl)" -Type Header

            $licenceColour = if ($headroom.Available -le 0) { 'Red' } else { 'Green' }
            Write-Host ("Active users: $($headroom.InUse)/$($headroom.Limit) " +
                "($($headroom.Available) free)") -ForegroundColor $licenceColour

            Write-Host "`nSeeded users ($($userReport.Count)):" -ForegroundColor Cyan
            $userReport | Format-Table Login, Status, Department, Clearance, Contractor -AutoSize |
                Out-String | Write-Host

            Write-Host "Groups ($($groupReport.Count)):" -ForegroundColor Cyan
            $groupReport | Format-Table Name, MemberCount -AutoSize | Out-String | Write-Host

            Write-Host "Group rules ($($ruleReport.Count)):" -ForegroundColor Cyan
            $ruleReport | Format-Table Name, Status, Expression -AutoSize | Out-String | Write-Host

            Write-Host "User types ($(@($report.UserTypes).Count) beyond the default):" -ForegroundColor Cyan
            $report.UserTypes | Format-Table Name, DisplayName -AutoSize | Out-String | Write-Host

            $attrHeading = 'Custom attributes ({0} across all schemas):' -f @($customAttributes).Count
            Write-Host $attrHeading -ForegroundColor Cyan
            $customAttributes | Format-Table UserType, Name, Type, Title -AutoSize | Out-String | Write-Host

            Write-Host "Apps ($(@($report.Apps).Count)):" -ForegroundColor Cyan
            $report.Apps | Format-Table Label, SignOnMode, GroupCount, UserCount -AutoSize |
                Out-String | Write-Host

            Write-Host "Network zones ($(@($report.NetworkZones).Count)):" -ForegroundColor Cyan
            $report.NetworkZones | Select-Object Name, Usage, Status,
                @{ Name = 'Gateways'; Expression = { $_.Gateways -join ', ' } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Policies ($(@($report.Policies).Count)):" -ForegroundColor Cyan
            $report.Policies | Format-Table Name, Type, Status, Priority -AutoSize |
                Out-String | Write-Host

            Write-Host "Trusted origins ($(@($report.TrustedOrigins).Count)):" -ForegroundColor Cyan
            $report.TrustedOrigins | Select-Object Name, Origin,
                @{ Name = 'Scopes'; Expression = { $_.Scopes -join ', ' } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Event hooks ($(@($report.EventHooks).Count)):" -ForegroundColor Cyan
            $report.EventHooks | Select-Object Name, Status, Uri,
                @{ Name = 'Events'; Expression = { @($_.Events).Count } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Linked objects ($(@($report.LinkedObjects).Count)):" -ForegroundColor Cyan
            $report.LinkedObjects | Format-Table Primary, Associated -AutoSize |
                Out-String | Write-Host
        }

        default {
            # The tenant cap is the constraint the whole module is shaped around, so an exhausted
            # licence is marked rather than stated in the same voice as everything else.
            $licenceLine = "Active users: $($headroom.InUse) of $($headroom.Limit), $($headroom.Available) free"
            $export = @{
                Report = $report; OutputFormat = $OutputFormat; OutputPath = $OutputPath
                FilePrefix = 'OktaLab'; Title = 'Okta Test Environment'
            }
            if ($headroom.Available -le 0) { $export['Warning'] = @($licenceLine) } else { $export['Note'] = @($licenceLine) }
            Export-TestEnvironmentReport @export
        }
    }

    if ($PassThru) { return $report }
}
