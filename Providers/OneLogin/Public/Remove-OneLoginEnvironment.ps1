function Remove-OneLoginEnvironment {
    <#
    .SYNOPSIS
        Removes every object this module created in a OneLogin account, proving ownership first

    .DESCRIPTION
        Reached through Remove-TestEnvironment once a OneLogin connection is active.

        Nothing is deleted for matching a name. Every object is selected by
        Get-OneLoginSeededObject: a person by the seed tag in its custom field and the prefix on its
        username; an app, an API authorization server and a self-registration profile by the tag in
        their text and the prefix on their name; a role or group by the prefix and by holding seeded
        people and nothing else; a policy by the seeded groups that use it; a mapping by the seed-tag
        condition and roles that are themselves proved; an app rule by its seeded app and seeded
        roles; the Smart Hook by the marker in its code and the seeded role it is gated on; a custom
        field by being declared here with the attribute prefix. A candidate that fails its proof is
        listed as left alone, with the reason, and never touched.

        Everything is proved before anything is deleted, because the proofs depend on each other.
        Then the deletions run in this order:

        1.  SelfRegistration and Hooks
        2.  Mappings          - so nothing re-adds a role while the rest goes
        3.  AppRules          - only when the apps they sit on are being kept; otherwise they go
                                with their apps
        4.  ApiAuthorizations - their scopes, claims and client links go with them
        5.  Roles             - their memberships and app grants go with them
        6.  Groups            - their members are left in no group
        7.  Policies
        8.  Apps              - with each app, the client secret New-OneLoginApp -SaveAppSecret
                                saved for it, record and vault secret both
        9.  Users             - their MFA factors go with them
        10. Attributes        - last, because a user without the seed tag field can no longer be
                                proved ours, and a teardown that stopped halfway has to be able to
                                finish

        Once the apps are gone, any saved app secret whose app is no longer in the account - one
        deleted by hand, or by a teardown that stopped before this existed - is deleted too, so saved
        secrets do not build up on the machine. Only this account's records are read, and a record
        whose content disagrees with its file name is never touched. With -Keep Apps no saved
        secret is touched at all.

        -Keep keeps what its proof needs as well: keeping a type keeps every type that type is proved
        by, read from the provider's proof dependency table, so nothing is left behind that the next
        teardown could not claim. What that adds is said.

        The confirmation is asked once, for the whole run, in the body of the function, and not in
        a begin{} block: a return inside begin{} ends that block and nothing else, so a refusal
        there would not stop the deletion. A session that cannot answer the prompt is refused too,
        so an automated teardown has to pass -Force.

        -WhatIf always wins over -Force. -Force lowers the confirmation preference and nothing
        else; every deletion still goes through ShouldProcess, so "-Force -WhatIf" deletes nothing
        and prints a line for every object it would have removed.

    .PARAMETER Keep
        Object types to leave in place, together with what their proof needs.

    .PARAMETER Force
        Remove without asking for confirmation. Required for any unattended teardown.

    .PARAMETER PassThru
        Return the results object.

    .OUTPUTS
        PSCustomObject describing what was removed and what was left alone, when -PassThru is used.

    .EXAMPLE
        PS> Remove-TestEnvironment -WhatIf

        DESCRIPTION: Lists everything teardown would remove, removing nothing
        OUTPUT: A What if: line per object, and the objects it would leave alone
        USE CASE: Checking ownership before deleting anything in an account you care about

    .EXAMPLE
        PS> Remove-TestEnvironment -Force -Keep Attributes -PassThru

        DESCRIPTION: Removes everything except the custom fields, unattended
        OUTPUT: The results object
        USE CASE: Tearing down between runs while keeping the fields, so the next seed is faster

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-OneLoginEnvironment
        Get-OneLoginEnvironmentReport
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The teardown summary is written for the person watching the run; the result object carries the same data for scripts.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('SelfRegistration', 'Hooks', 'Mappings', 'AppRules', 'ApiAuthorizations', 'Roles', 'Groups', 'Policies', 'Apps', 'Users', 'Attributes')]
        [string[]]$Keep = @(),

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting Remove-OneLoginEnvironment - CorrelationId: $correlationId"

    $connection = Get-OneLoginConnection

    $order = @('SelfRegistration', 'Hooks', 'Mappings', 'AppRules', 'ApiAuthorizations', 'Roles', 'Groups', 'Policies', 'Apps', 'Users', 'Attributes')
    $removed = [ordered]@{}
    foreach ($type in $order) { $removed[$type] = 0 }
    $errors = [System.Collections.Generic.List[string]]::new()
    $leftAlone = [System.Collections.Generic.List[object]]::new()
    $appSecretsRemoved = 0

    $buildResult = {
        param([bool]$Cancelled)
        [PSCustomObject]@{
            CorrelationId = $correlationId
            Subdomain     = $connection.Subdomain
            Cancelled     = $Cancelled
            Removed       = [PSCustomObject]$removed
            TotalRemoved      = ($removed.Values | Measure-Object -Sum).Sum
            AppSecretsRemoved = $appSecretsRemoved
            LeftAlone         = $leftAlone.ToArray()
            Errors            = $errors.ToArray()
        }
    }

    # One confirmation for the run, asked here in the body where a refusal actually stops the
    # function. Skipped under -WhatIf, because a preview changes nothing and demanding an answer
    # before showing what would happen made -WhatIf unusable from anything non-interactive.
    if (-not $WhatIfPreference) {
        $question = "Remove every object this module created in OneLogin account '$($connection.Subdomain)'?"
        $confirmed = $Force
        if (-not $confirmed) {
            $confirmed = Confirm-TestTeardown -Cmdlet $PSCmdlet -Question $question -Caption 'Remove OneLogin test environment'
        }
        if (-not $confirmed) {
            Write-Host 'Teardown cancelled. Nothing was removed. Pass -Force to remove without being asked.'
            if ($PassThru) { return (& $buildResult $true) }
            return
        }
        # Asked once; every deletion below still passes through ShouldProcess, so -WhatIf is never
        # defeated by this.
        $ConfirmPreference = 'None'
    }

    Write-TestMessage -Message ('OneLogin Test Environment Teardown ({0}.onelogin.com)' -f $connection.Subdomain) -Type Header

    # Keeping a type keeps everything its proof reads, transitively.
    $kept = New-Object 'System.Collections.Generic.HashSet[string]'
    $pending = New-Object System.Collections.Generic.Queue[string]
    foreach ($type in $Keep) { $pending.Enqueue($type) }
    while ($pending.Count -gt 0) {
        $type = $pending.Dequeue()
        if (-not $kept.Add($type)) { continue }
        foreach ($dependency in @($script:OneLoginProofDependency[$type])) { if ($dependency) { $pending.Enqueue($dependency) } }
    }
    $implied = @($kept | Where-Object { $Keep -notcontains $_ } | Sort-Object)
    if ($implied.Count -gt 0) {
        $errors.Add(('Also kept, because what -Keep keeps is proved by them and without them no later teardown could claim it: {0}.' -f ($implied -join ', ')))
    }

    # Everything proved first, while every proof still stands.
    $users = @(Get-OneLoginSeededObject -Type Users -Connection $connection)
    $apps = @(Get-OneLoginSeededObject -Type Apps -Connection $connection)
    $userIds = @($users | ForEach-Object { [string]$_.id })
    $appIds = @($apps | ForEach-Object { [string]$_.id })
    $roles = @(Get-OneLoginSeededObject -Type Roles -OwnedUserId $userIds -OwnedAppId $appIds -Connection $connection)
    $roleIds = @($roles | ForEach-Object { [string]$_.id })
    $groups = @(Get-OneLoginSeededObject -Type Groups -OwnedUserId $userIds -Connection $connection)
    $groupIds = @($groups | ForEach-Object { [string]$_.id })
    $owned = @{ OwnedUserId = $userIds; OwnedAppId = $appIds; OwnedRoleId = $roleIds; OwnedGroupId = $groupIds; Connection = $connection }
    $found = [ordered]@{
        SelfRegistration  = @(Get-OneLoginSeededObject -Type SelfRegistration -Connection $connection)
        Hooks             = @(Get-OneLoginSeededObject -Type Hooks @owned)
        Mappings          = @(Get-OneLoginSeededObject -Type Mappings @owned)
        AppRules          = @(Get-OneLoginSeededObject -Type AppRules @owned)
        ApiAuthorizations = @(Get-OneLoginSeededObject -Type ApiAuthorizations -Connection $connection)
        Roles             = $roles
        Groups            = $groups
        Policies          = @(Get-OneLoginSeededObject -Type Policies @owned)
        Apps              = $apps
        Users             = $users
        Attributes        = @(Get-OneLoginSeededObject -Type Attributes -Connection $connection)
    }

    foreach ($type in 'SelfRegistration', 'Hooks', 'Mappings', 'AppRules', 'ApiAuthorizations', 'Roles', 'Groups', 'Policies', 'Apps') {
        foreach ($refused in @(Get-OneLoginSeededObject -Type $type -Unproven @owned)) { $leftAlone.Add($refused) }
    }

    $noun = @{
        SelfRegistration = 'self-registration profile'; Hooks = 'Smart Hook'; Mappings = 'mapping'; AppRules = 'app rule'
        ApiAuthorizations = 'API authorization server'; Roles = 'role'; Groups = 'group'; Policies = 'user policy'; Apps = 'app'
        Users = 'user'; Attributes = 'custom user field'
    }
    $pathOf = {
        param([string]$Type, $Object)
        switch ($Type) {
            'SelfRegistration' { "self_registration_profiles/$($Object.id)" }
            'Hooks' { "hooks/$($Object.id)" }
            'Mappings' { "mappings/$($Object.id)" }
            'AppRules' { "apps/$($Object.AppId)/rules/$($Object.id)" }
            'ApiAuthorizations' { "api_authorizations/$($Object.id)" }
            'Roles' { "roles/$($Object.id)" }
            'Groups' { "groups/$($Object.id)" }
            'Policies' { "policies/$($Object.id)" }
            'Apps' { "apps/$($Object.id)" }
            'Users' { "users/$($Object.id)" }
            'Attributes' { "users/custom_attributes/$($Object.id)" }
        }
    }
    $labelOf = {
        param([string]$Type, $Object)
        if ($Type -eq 'Users') { return [string]$Object.username }
        if ($Type -eq 'Attributes') { return [string]$Object.shortname }
        return [string]$Object.name
    }

    # Saved app secrets, by the app they open. Read only when the apps are going.
    $secretByAppId = @{}
    if (-not $kept.Contains('Apps')) {
        foreach ($record in @(Get-OneLoginAppSecretRecord -Subdomain $connection.Subdomain)) { $secretByAppId[$record.AppId] = $record }
    }
    $removeSecret = {
        param($Record)
        try {
            if (Remove-OneLoginAppSecret -Record $Record) { $secretsDeleted.Add($Record.Path) }
        }
        catch {
            $errors.Add("Could not delete the saved client secret at $($Record.Path): $($_.Exception.Message)")
        }
    }
    $secretsDeleted = [System.Collections.Generic.List[string]]::new()

    foreach ($type in $order) {
        if ($kept.Contains($type)) { continue }
        # An app rule goes with its app; it is deleted on its own only when the app stays.
        if ($type -eq 'AppRules' -and -not $kept.Contains('Apps')) { continue }
        if (@($found[$type]).Count -eq 0) { continue }

        Write-Host ('Removing {0}' -f $noun[$type])
        foreach ($object in $found[$type]) {
            $label = & $labelOf $type $object
            $secret = if ($type -eq 'Apps') { $secretByAppId[[string]$object.id] } else { $null }
            if (-not $PSCmdlet.ShouldProcess($label, "Delete OneLogin $($noun[$type])")) {
                # Under -WhatIf, name the saved secret that would go with the app; it removes nothing.
                if ($secret) { & $removeSecret $secret }
                continue
            }
            try {
                $null = Invoke-OneLoginRequest -Method DELETE -Path (& $pathOf $type $object) -Connection $connection -IgnoreStatus 404
                $removed[$type]++
                if ($secret) {
                    & $removeSecret $secret
                    $secretByAppId.Remove([string]$object.id)
                }
            }
            catch {
                $errors.Add("Could not delete $($noun[$type]) '${label}': $($_.Exception.Message)")
                Write-Warning "Could not delete $($noun[$type]) '${label}': $($_.Exception.Message)"
            }
        }
    }

    # Saved secrets whose app is no longer in the account, whatever removed it. Read against every
    # app in the account, not only the seeded ones, so a record is never deleted while its app lives.
    if (-not $kept.Contains('Apps') -and $secretByAppId.Count -gt 0) {
        $liveAppIds = $null
        try {
            $liveAppIds = @(Invoke-OneLoginRequest -Method GET -Path 'apps' -Paginate -Connection $connection |
                    Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })
        }
        catch {
            $errors.Add("Could not list the account's apps, so saved client secrets of apps deleted elsewhere were left: $($_.Exception.Message)")
        }
        if ($null -ne $liveAppIds) {
            foreach ($appId in @($secretByAppId.Keys)) {
                if ($liveAppIds -notcontains $appId) { & $removeSecret $secretByAppId[$appId] }
            }
        }
    }
    $appSecretsRemoved = $secretsDeleted.Count

    $result = & $buildResult $false

    Write-TestMessage -Message 'Teardown Summary' -Type Header
    Write-Host ('Objects removed: {0}' -f $result.TotalRemoved)
    foreach ($type in $removed.Keys) { Write-Host ('  {0,-17} {1}' -f $type, $removed[$type]) }
    if ($appSecretsRemoved -gt 0) { Write-Host ('Saved app secrets deleted from this machine: {0}' -f $appSecretsRemoved) }
    if ($leftAlone.Count -gt 0) {
        Write-Host ('Left alone, because they could not be proved seeded: {0}' -f $leftAlone.Count)
        foreach ($item in $leftAlone) { Write-Host ('  {0} {1} ({2}): {3}' -f $noun[$item.Type], $item.Name, $item.Id, $item.Reason) }
    }
    foreach ($message in $errors) { Write-Host ('  ! {0}' -f $message) }

    if ($PassThru) { return $result }
}
