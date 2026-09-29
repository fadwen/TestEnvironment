function Get-OneLoginEnvironmentReport {
    <#
    .SYNOPSIS
        Reports what this module has seeded in a OneLogin account, and what shape it is in

    .DESCRIPTION
        Reached through Get-TestEnvironmentReport once a OneLogin connection is active.

        Only objects this module can prove it created are counted, using the same selection
        teardown uses, so the report and the teardown can never disagree about what is ours.

        Beyond counts, it surfaces the states the seed exists to create, because a report that
        says "321 users" and nothing else proves nothing about whether a script handles a
        suspended manager or a rejected partner who still holds a role:

        - Users by status and by state, the two numbers OneLogin keeps a lifecycle in.
        - Roles with their user and app counts. A role an enabled mapping adds people to holds
          more than the data lists, and only once OneLogin has run the mapping.
        - Groups with their member counts and policy, apps by connector and visibility, and
          mappings with whether each is enabled.
        - User policies with the groups they govern and their password and lockout settings, API
          authorization servers with their scopes and clients, app rules, the Smart Hook with
          whether it is disabled (it should always be), and the sign-up profile with whether it is
          enabled and moderated.

        Read-only. Nothing in the account changes.

        Console output is for a person; JSON, CSV and HTML are for a file, written by the one
        writer every provider shares, as UTF-8. The report object is the shape every provider
        returns: Provider, Target, GeneratedOn, the account's own facts, Counts, Sections, and one
        property per section.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console.

    .PARAMETER PassThru
        Returns the report object as well.

    .OUTPUTS
        OneLoginEnvironmentReport, when -PassThru is supplied.

    .EXAMPLE
        PS> Get-TestEnvironmentReport

        DESCRIPTION: Summarises the seeded account
        OUTPUT: Counts and state breakdowns per object type
        USE CASE: Confirming a seed produced what it should

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-OneLoginEnvironment
        Remove-OneLoginEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The summary is written for a person reading it; -PassThru returns the object for scripts.')]
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

    $connection = Get-OneLoginConnection
    if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $attributes = @(Get-OneLoginSeededObject -Type Attributes -Connection $connection)
    $users = @(Get-OneLoginSeededObject -Type Users -Connection $connection)
    $apps = @(Get-OneLoginSeededObject -Type Apps -Connection $connection)
    $userIds = @($users | ForEach-Object { [string]$_.id })
    $appIds = @($apps | ForEach-Object { [string]$_.id })
    $roles = @(Get-OneLoginSeededObject -Type Roles -OwnedUserId $userIds -OwnedAppId $appIds -Connection $connection)
    $groups = @(Get-OneLoginSeededObject -Type Groups -OwnedUserId $userIds -Connection $connection)
    $owned = @{ OwnedUserId = $userIds; OwnedAppId = $appIds; OwnedRoleId = @($roles | ForEach-Object { [string]$_.id }); OwnedGroupId = @($groups | ForEach-Object { [string]$_.id }); Connection = $connection }
    $mappings = @(Get-OneLoginSeededObject -Type Mappings @owned)
    $policies = @(Get-OneLoginSeededObject -Type Policies @owned)
    $apiServers = @(Get-OneLoginSeededObject -Type ApiAuthorizations -Connection $connection)
    $appRules = @(Get-OneLoginSeededObject -Type AppRules @owned)
    $hooks = @(Get-OneLoginSeededObject -Type Hooks @owned)
    $registrations = @(Get-OneLoginSeededObject -Type SelfRegistration -Connection $connection)

    $nameOf = {
        param($map, $value)
        foreach ($entry in $map.GetEnumerator()) { if ([int]$entry.Value -eq [int]$value) { return $entry.Key } }
        return [string]$value
    }

    $groupName = @{}
    foreach ($group in $groups) { $groupName[[string]$group.id] = $group.name }
    $userName = @{}
    foreach ($user in $users) { $userName[[string]$user.id] = $user.username }
    $connectorName = @{}
    foreach ($entry in $script:OneLoginConnector.GetEnumerator()) { $connectorName[[int]$entry.Value] = $entry.Key }

    $byStatus = [ordered]@{}
    foreach ($bucket in ($users | Group-Object { & $nameOf $script:OneLoginUserStatus $_.status } | Sort-Object Name)) { $byStatus[$bucket.Name] = $bucket.Count }
    $byState = [ordered]@{}
    foreach ($bucket in ($users | Group-Object { & $nameOf $script:OneLoginUserState $_.state } | Sort-Object Name)) { $byState[$bucket.Name] = $bucket.Count }

    $userRows = foreach ($user in ($users | Sort-Object username)) {
        [PSCustomObject]@{
            Username   = $user.username
            FirstName  = $user.firstname
            LastName   = $user.lastname
            Status     = & $nameOf $script:OneLoginUserStatus $user.status
            State      = & $nameOf $script:OneLoginUserState $user.state
            Group      = $(if ($user.group_id) { $groupName[[string]$user.group_id] } else { $null })
            Manager    = $(if ($user.manager_user_id) { $userName[[string]$user.manager_user_id] } else { $null })
            Roles      = @($user.role_ids).Count
            Contractor = $(if ($user.custom_attributes) { $user.custom_attributes.zztest_contractor } else { $null })
            AdUserName = $user.samaccountname
            Locale     = $user.preferred_locale_code
            LockedUntil = $user.locked_until
        }
    }
    $roleRows = foreach ($role in ($roles | Sort-Object name)) {
        [PSCustomObject]@{ Name = $role.name; Users = @($role.users).Count; Apps = @($role.apps).Count }
    }
    $policyName = @{}
    foreach ($policy in $policies) { $policyName[[string]$policy.id] = $policy.name }
    $groupRows = foreach ($group in ($groups | Sort-Object name)) {
        [PSCustomObject]@{ Name = $group.name; Members = @($group.MemberIds).Count; Policy = $(if ($group.policy_id) { $policyName[[string]$group.policy_id] } else { $null }) }
    }
    $policyRows = foreach ($policy in ($policies | Sort-Object name)) {
        $detail = Invoke-OneLoginRequest -Method GET -Path "policies/$($policy.id)" -Connection $connection
        [PSCustomObject]@{
            Name                   = $policy.name
            Groups                 = @($policy.GroupIds).Count
            MinimumPasswordLength  = $detail.minimum_password_length
            PasswordExpirationDays = $detail.password_expiration_days
            MaxInvalidAttempts     = $detail.maximum_invalid_login_attempts
            LockMinutes            = $detail.lock_effective_minutes
        }
    }
    $apiRows = foreach ($server in ($apiServers | Sort-Object name)) {
        $scopes = @(Invoke-OneLoginRequest -Method GET -Path "api_authorizations/$($server.id)/scopes" -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
        $clients = @(Invoke-OneLoginRequest -Method GET -Path "api_authorizations/$($server.id)/clients" -Connection $connection | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
        [PSCustomObject]@{ Name = $server.name; Audience = @($server.configuration.audiences) -join ' '; Scopes = @($scopes | ForEach-Object value); Clients = $clients.Count }
    }
    $appName = @{}
    foreach ($app in $apps) { $appName[[string]$app.id] = $app.name }
    $appRuleRows = foreach ($rule in ($appRules | Sort-Object name)) {
        [PSCustomObject]@{ App = $appName[[string]$rule.AppId]; Name = $rule.name; Enabled = [bool]$rule.enabled }
    }
    $hookRows = foreach ($hook in $hooks) {
        [PSCustomObject]@{ Type = $hook.type; Id = $hook.id; Disabled = [bool]$hook.disabled; Conditions = @($hook.conditions).Count }
    }
    $registrationRows = foreach ($registration in ($registrations | Sort-Object name)) {
        [PSCustomObject]@{ Name = $registration.name; Enabled = [bool]$registration.enabled; Moderated = [bool]$registration.moderated; Domains = $registration.domain_whitelist }
    }
    # An app's roles are counted from the roles, because the app listing leaves role_ids out.
    $rolesOfApp = @{}
    foreach ($role in $roles) {
        foreach ($id in @($role.apps | Where-Object { $null -ne $_ })) { $rolesOfApp[[string]$id] = 1 + [int]$rolesOfApp[[string]$id] }
    }
    # Whether New-OneLoginApp -SaveAppSecret kept the app's secret on this machine. Read from the
    # records alone; no secret is decrypted for a report.
    $savedSecret = @{}
    foreach ($record in @(Get-OneLoginAppSecretRecord -Subdomain $connection.Subdomain)) { $savedSecret[$record.AppId] = $record.Protection }
    $appRows = foreach ($app in ($apps | Sort-Object name)) {
        $connector = if ($connectorName.ContainsKey([int]$app.connector_id)) { $connectorName[[int]$app.connector_id] } else { [string]$app.connector_id }
        $secret = if ($savedSecret.ContainsKey([string]$app.id)) { $savedSecret[[string]$app.id] } else { '' }
        [PSCustomObject]@{ Name = $app.name; Connector = $connector; Visible = [bool]$app.visible; Roles = [int]$rolesOfApp[[string]$app.id]; SecretSaved = $secret }
    }
    $mappingRows = foreach ($mapping in ($mappings | Sort-Object name)) {
        [PSCustomObject]@{ Name = $mapping.name; Enabled = [bool]$mapping.enabled; Conditions = @($mapping.conditions).Count; Actions = @($mapping.actions).Count }
    }
    $attributeRows = foreach ($field in ($attributes | Sort-Object shortname)) {
        [PSCustomObject]@{ Shortname = $field.shortname; Name = $field.name }
    }

    $report = New-TestEnvironmentReport -Provider 'OneLogin' -Target $connection.Subdomain -TypeName 'OneLoginEnvironmentReport' `
        -Property ([ordered]@{
            Subdomain          = $connection.Subdomain
            AccountId          = $connection.AccountId
            Prefix             = $connection.Prefix
            UsersByStatus      = [PSCustomObject]$byStatus
            UsersByState       = [PSCustomObject]$byState
            UsersWithManager   = @($users | Where-Object { $_.manager_user_id }).Count
            UsersInNoGroup     = @($users | Where-Object { -not $_.group_id }).Count
            UsersLocked        = @($users | Where-Object { [int]$_.status -eq $script:OneLoginUserStatus['Locked'] }).Count
        }) `
        -Section ([ordered]@{
            Attributes = @($attributeRows)
            Users      = @($userRows)
            Roles      = @($roleRows)
            Groups     = @($groupRows)
            Apps       = @($appRows)
            Mappings   = @($mappingRows)
            Policies   = @($policyRows)
            ApiAuthorizations = @($apiRows)
            AppRules   = @($appRuleRows)
            Hooks      = @($hookRows)
            SelfRegistration = @($registrationRows)
        })

    if ($OutputFormat -eq 'Console') {
        Write-TestMessage -Message ('OneLogin Test Environment Report ({0}.onelogin.com)' -f $connection.Subdomain) -Type Header
        Write-Host 'Counts'
        foreach ($property in $report.Counts.PSObject.Properties) { Write-Host ('  {0,-12} {1}' -f $property.Name, $property.Value) }
        Write-Host ''
        Write-Host 'Users by status'
        foreach ($property in $report.UsersByStatus.PSObject.Properties) { Write-Host ('  {0,-24} {1}' -f $property.Name, $property.Value) }
        Write-Host 'Users by state'
        foreach ($property in $report.UsersByState.PSObject.Properties) { Write-Host ('  {0,-24} {1}' -f $property.Name, $property.Value) }
        Write-Host ('  with a manager {0}, in no group {1}' -f $report.UsersWithManager, $report.UsersInNoGroup)
        Write-Host ''
        Write-Host 'Roles'
        $report.Roles | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'Groups'
        $report.Groups | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'Apps'
        $report.Apps | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'Mappings'
        $report.Mappings | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'Policies'
        $report.Policies | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'API authorizations'
        $report.ApiAuthorizations | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'App rules, Smart Hooks and sign-up'
        $report.AppRules | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        $report.Hooks | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        $report.SelfRegistration | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
    }
    else {
        Export-TestEnvironmentReport -Report $report -OutputFormat $OutputFormat -OutputPath $OutputPath `
            -FilePrefix 'OneLoginLab' -Title 'OneLogin Test Environment Report' `
            -Note @("Account $($connection.Subdomain).onelogin.com")
    }

    if ($PassThru) { return $report }
}
