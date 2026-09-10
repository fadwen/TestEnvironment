function Remove-AuthentikEnvironment {
    <#
    .SYNOPSIS
        Removes everything the seed created, proving ownership of each object first

    .DESCRIPTION
        Tears down in the reverse of the order the seed built: policy bindings and policies,
        then applications and the providers behind them, then users, then groups deepest
        first, then notification rules and their transports. Nothing is deleted for merely
        carrying the prefix. Each type has to satisfy the evidence the seed wrote - the tag in
        a user's or group's attributes, the marker in an application's description, a
        provider's attachment to a seeded application - and Get-AuthentikSeededObject is the
        one place that evidence is judged.

        The automation service account is a seeded user and is the one that must not be
        deleted while it is the credential in use, so it is kept unless -RemoveServiceAccount
        is passed, and then removed last. Its credential record goes with it only under
        -RemoveCredentialFile, and the vault secret the record names is read before the file
        is deleted, or the secret is orphaned.

        -WhatIf wins over -Force. -Force suppresses the prompts by setting the confirm
        preference rather than by bypassing ShouldProcess, so ShouldProcess still runs and
        still returns false under -WhatIf. That distinction is pinned by the tests because
        -Force defeating -WhatIf was the worst defect an earlier module shipped.

    .PARAMETER Keep
        Object types to leave in place: Policies, Applications, Users, Groups,
        NotificationRules.

    .PARAMETER RemoveServiceAccount
        Also delete the automation service account. It is removed last, after everything it
        was used to remove.

    .PARAMETER RemoveCredentialFile
        With -RemoveServiceAccount, also delete the credential record and the vault secret it
        names.

    .PARAMETER Force
        Do not prompt. Has no effect under -WhatIf.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with BaseUrl, Prefix, StartTime, EndTime and a Removed and Errors list
        per object type.

    .EXAMPLE
        PS> Remove-AuthentikEnvironment -WhatIf

        DESCRIPTION: Lists everything that would be removed
        OUTPUT: One WhatIf line per object the module can prove it owns
        USE CASE: Always the first teardown call

    .EXAMPLE
        PS> Remove-AuthentikEnvironment -Keep Groups -Force -PassThru

        DESCRIPTION: Removes everything except the groups, without prompting
        OUTPUT: The result object with counts per type
        USE CASE: Re-seeding users against groups a report was already written against

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The teardown summary is written for the person watching; the result object carries the same data.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Keep',
        Justification = 'Read inside the per-type sweep, which the analyzer does not follow.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Invitations', 'Tokens', 'Bindings', 'Policies', 'Entitlements', 'Applications',
            'ScopeMappings', 'Roles', 'Users', 'Groups', 'NotificationRules')]
        [string[]]$Keep = @(),

        [Parameter()]
        [switch]$RemoveServiceAccount,

        [Parameter()]
        [switch]$RemoveCredentialFile,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $results = [PSCustomObject]@{
        BaseUrl           = $connection.BaseUrl
        Prefix            = $connection.Prefix
        StartTime         = Get-Date
        EndTime           = $null
        Invitations       = @{ Removed = @(); Errors = @() }
        Tokens            = @{ Removed = @(); Errors = @() }
        Bindings          = @{ Removed = @(); Errors = @() }
        Policies          = @{ Removed = @(); Errors = @() }
        Entitlements      = @{ Removed = @(); Errors = @() }
        Applications      = @{ Removed = @(); Errors = @() }
        Providers         = @{ Removed = @(); Errors = @() }
        ScopeMappings     = @{ Removed = @(); Errors = @() }
        Roles             = @{ Removed = @(); Errors = @() }
        Users             = @{ Removed = @(); Errors = @() }
        Groups            = @{ Removed = @(); Errors = @() }
        NotificationRules = @{ Removed = @(); Errors = @() }
        ServiceAccount    = @{ Removed = @(); Errors = @() }
    }

    Write-TestMessage -Message "Authentik Test Environment Teardown ($($connection.BaseUrl))" -Type Header

    # Read directly rather than through ShouldProcess alone, so -Force can skip the prompt
    # without also skipping the preview.
    $isWhatIf = $WhatIfPreference

    # -Force sets the preference rather than short-circuiting ShouldProcess, which is what
    # keeps -WhatIf working: ShouldProcess is still called and still returns false under it.
    if ($Force -and -not $isWhatIf) {
        $ConfirmPreference = 'None'
    }

    if (-not $Force -and -not $isWhatIf) {
        $prompt = ("This permanently deletes every user, group, role, application, provider, scope mapping, " +
            "entitlement, policy, binding, token, invitation and notification rule tagged '$($marker.Tag)' " +
            "in $($connection.BaseUrl). Authentik has no undo.")
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Remove Authentik test environment')) {
            Write-TestMessage -Message 'Teardown cancelled.' -Type Warning
            if ($PassThru) { return $results }
            return
        }
    }

    # A sweep is: find what we own, confirm each, delete each, record the outcome. The
    # deletion path takes the object's key so each type can name its own.
    $sweep = {
        param($key, $label, $one, $items, $nameOf, $pathOf)
        Write-TestMessage -Message "Removing $label" -Type Info
        foreach ($item in $items) {
            $name = & $nameOf $item
            if (-not $PSCmdlet.ShouldProcess($name, "Delete Authentik $one")) { continue }
            try {
                $null = Invoke-AuthentikRequest -Method DELETE -Path (& $pathOf $item) -Connection $connection
                $results.$key.Removed += $name
            }
            catch {
                $results.$key.Errors += "${name}: $($_.Exception.Message)"
                Write-Error "Failed to delete '$name': $($_.Exception.Message)"
            }
        }
    }

    # --- 1. Invitations and tokens, which depend on nothing ---------------------------------
    if ('Invitations' -notin $Keep) {
        try {
            $invitations = @(Get-AuthentikSeededObject -Type Invitations -Connection $connection)
            & $sweep 'Invitations' 'invitations' 'invitation' $invitations { param($i) $i.name } { param($i) "/stages/invitation/invitations/$($i.pk)/" }
        }
        catch {
            $results.Invitations.Errors += $_.Exception.Message
            Write-Error "Could not enumerate invitations: $($_.Exception.Message)"
        }
    }

    if ('Tokens' -notin $Keep) {
        try {
            $tokens = @(Get-AuthentikSeededObject -Type Tokens -Connection $connection)
            & $sweep 'Tokens' 'tokens' 'token' $tokens { param($t) $t.identifier } { param($t) "/core/tokens/$($t.identifier)/" }
        }
        catch {
            $results.Tokens.Errors += $_.Exception.Message
            Write-Error "Could not enumerate tokens: $($_.Exception.Message)"
        }
    }

    # --- 2. Bindings on every seeded target --------------------------------------------------
    # A binding on a seeded application, entitlement or rule is ours whatever it carries, and
    # removing them first means a policy or group that is kept is cleanly detached rather than
    # left pointing at a target that is about to go.
    if ('Bindings' -notin $Keep) {
        try {
            $bindingTargets = @()
            foreach ($application in @(Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
                $bindingTargets += @{ Uuid = [string]$application.pbm_uuid; Name = $application.slug }
            }
            foreach ($entitlement in @(Get-AuthentikSeededObject -Type Entitlements -Connection $connection)) {
                $bindingTargets += @{ Uuid = [string]$entitlement.pbm_uuid; Name = $entitlement.name }
            }
            foreach ($rule in @(Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)) {
                $bindingTargets += @{ Uuid = [string]$rule.pk; Name = $rule.name }
            }
            foreach ($bindingTarget in $bindingTargets) {
                $bindings = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                        -Query @{ target = $bindingTarget.Uuid } -Connection $connection -Paginate)
                $targetName = $bindingTarget.Name
                & $sweep 'Bindings' "bindings on $targetName" 'policy binding' $bindings `
                    { param($b) 'binding {0} on {1}' -f $b.pk, $targetName } `
                    { param($b) "/policies/bindings/$($b.pk)/" }
            }
        }
        catch {
            $results.Bindings.Errors += $_.Exception.Message
            Write-Error "Could not enumerate bindings: $($_.Exception.Message)"
        }
    }

    # --- 3. Policies, then entitlements ------------------------------------------------------
    if ('Policies' -notin $Keep) {
        try {
            $policies = @(Get-AuthentikSeededObject -Type Policies -Connection $connection)
            & $sweep 'Policies' 'policies' 'policy' $policies { param($p) $p.name } { param($p) "/policies/all/$($p.pk)/" }
        }
        catch {
            $results.Policies.Errors += $_.Exception.Message
            Write-Error "Could not enumerate policies: $($_.Exception.Message)"
        }
    }

    if ('Entitlements' -notin $Keep) {
        try {
            $entitlements = @(Get-AuthentikSeededObject -Type Entitlements -Connection $connection)
            & $sweep 'Entitlements' 'application entitlements' 'application entitlement' $entitlements `
                { param($e) '{0} on {1}' -f $e.name, $e.app_slug } { param($e) "/core/application_entitlements/$($e.pbm_uuid)/" }
        }
        catch {
            $results.Entitlements.Errors += $_.Exception.Message
            Write-Error "Could not enumerate entitlements: $($_.Exception.Message)"
        }
    }

    # --- 4. Applications, the providers behind them, then the scope mappings they carried ---
    if ('Applications' -notin $Keep) {
        try {
            $applications = @(Get-AuthentikSeededObject -Type Applications -Connection $connection)
            & $sweep 'Applications' 'applications' 'application' $applications { param($a) $a.name } { param($a) "/core/applications/$($a.slug)/" }
            $providers = @(Get-AuthentikSeededObject -Type Providers -Connection $connection)
            & $sweep 'Providers' 'providers' 'provider' $providers { param($p) $p.name } { param($p) "/providers/all/$($p.pk)/" }
        }
        catch {
            $results.Applications.Errors += $_.Exception.Message
            Write-Error "Could not enumerate applications: $($_.Exception.Message)"
        }
    }

    if ('ScopeMappings' -notin $Keep) {
        try {
            $mappings = @(Get-AuthentikSeededObject -Type ScopeMappings -Connection $connection)
            & $sweep 'ScopeMappings' 'scope mappings' 'scope mapping' $mappings { param($m) $m.name } { param($m) "/propertymappings/provider/scope/$($m.pk)/" }
        }
        catch {
            $results.ScopeMappings.Errors += $_.Exception.Message
            Write-Error "Could not enumerate scope mappings: $($_.Exception.Message)"
        }
    }

    # --- 5. Roles, before the groups that hold them ------------------------------------------
    if ('Roles' -notin $Keep) {
        try {
            $roles = @(Get-AuthentikSeededObject -Type Roles -Connection $connection)
            & $sweep 'Roles' 'roles' 'role' $roles { param($r) $r.name } { param($r) "/rbac/roles/$($r.pk)/" }
        }
        catch {
            $results.Roles.Errors += $_.Exception.Message
            Write-Error "Could not enumerate roles: $($_.Exception.Message)"
        }
    }

    # --- 6. Users ----------------------------------------------------------------------------
    if ('Users' -notin $Keep) {
        try {
            $users = @(Get-AuthentikSeededObject -Type Users -Connection $connection)
            & $sweep 'Users' 'users' 'user' $users { param($u) $u.username } { param($u) "/core/users/$($u.pk)/" }
        }
        catch {
            $results.Users.Errors += $_.Exception.Message
            Write-Error "Could not enumerate users: $($_.Exception.Message)"
        }
    }

    # --- 7. Groups, deepest first ------------------------------------------------------------
    # A child names its parents, so removing the leaves first leaves nothing dangling if a
    # deletion midway fails.
    if ('Groups' -notin $Keep) {
        try {
            $groups = @(Get-AuthentikSeededObject -Type Groups -Connection $connection)

            # Depth is walked, not counted: a leaf and its parent both have one parent each.
            $byPk = @{}
            foreach ($group in $groups) { $byPk[[string]$group.pk] = $group }
            $depthOf = {
                param($group)
                $depth = 0
                $frontier = @([string[]]$group.parents)
                while ($frontier.Count -gt 0 -and $depth -lt 20) {
                    $depth++
                    $frontier = @($frontier | ForEach-Object { if ($byPk.ContainsKey($_)) { [string[]]$byPk[$_].parents } })
                }
                $depth
            }
            $ordered = @($groups | Sort-Object -Property @{ Expression = { & $depthOf $_ }; Descending = $true }, name)
            & $sweep 'Groups' 'groups' 'group' $ordered { param($g) $g.name } { param($g) "/core/groups/$($g.pk)/" }
        }
        catch {
            $results.Groups.Errors += $_.Exception.Message
            Write-Error "Could not enumerate groups: $($_.Exception.Message)"
        }
    }

    # --- 8. Notification rules, then their transports ---------------------------------------
    if ('NotificationRules' -notin $Keep) {
        try {
            $rules = @(Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)
            & $sweep 'NotificationRules' 'notification rules' 'notification rule' $rules { param($r) $r.name } { param($r) "/events/rules/$($r.pk)/" }
            $transports = @(Get-AuthentikSeededObject -Type NotificationTransports -Connection $connection)
            & $sweep 'NotificationRules' 'notification transports' 'notification transport' $transports { param($t) $t.name } { param($t) "/events/transports/$($t.pk)/" }
        }
        catch {
            $results.NotificationRules.Errors += $_.Exception.Message
            Write-Error "Could not enumerate notification rules: $($_.Exception.Message)"
        }
    }

    # --- 9. The service account, last --------------------------------------------------------
    if ($RemoveServiceAccount) {
        try {
            $accountName = Get-AuthentikServiceAccountName -Marker $marker
            $account = @(Get-AuthentikSeededObject -Type Users -IncludeServiceAccount -Connection $connection |
                    Where-Object { $_.username -eq $accountName })

            if ($connection.AuthType -eq 'ServiceAccount' -and $account.Count -gt 0) {
                Write-Warning "Removing the service account this session is connected as. Nothing else will work afterwards until you reconnect with an API token."
            }

            & $sweep 'ServiceAccount' 'the service account' 'service account' $account { param($u) $u.username } { param($u) "/core/users/$($u.pk)/" }

            if ($RemoveCredentialFile) {
                $recordPath = Get-AuthentikCredentialPath -BaseUrl $connection.BaseUrl -Path $connection.CredentialPath
                if (Test-Path -LiteralPath $recordPath) {
                    if ($PSCmdlet.ShouldProcess($recordPath, 'Delete the service account credential record')) {
                        # The vault pointer is read before the file goes, or the secret is orphaned.
                        $record = $null
                        try { $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } catch { $record = $null }
                        if ($record -and $record.PSObject.Properties['secretName'] -and $record.secretName) {
                            try { Remove-TestVaultSecret -VaultName $record.vaultName -SecretName $record.secretName -Confirm:$false }
                            catch { Write-Warning "Could not remove the vault secret '$($record.secretName)': $($_.Exception.Message)" }
                        }
                        Remove-Item -LiteralPath $recordPath -Force
                        $results.ServiceAccount.Removed += $recordPath
                    }
                }
            }
        }
        catch {
            $results.ServiceAccount.Errors += $_.Exception.Message
            Write-Error "Could not remove the service account: $($_.Exception.Message)"
        }
    }

    $results.EndTime = Get-Date

    $tracked = @('Invitations', 'Tokens', 'Bindings', 'Policies', 'Entitlements', 'Applications', 'Providers',
        'ScopeMappings', 'Roles', 'Users', 'Groups', 'NotificationRules', 'ServiceAccount')
    $removedCount = @($tracked | ForEach-Object { @($results.$_.Removed).Count } | Measure-Object -Sum).Sum
    $errorCount = @($tracked | ForEach-Object { @($results.$_.Errors).Count } | Measure-Object -Sum).Sum

    Write-TestMessage -Message 'Teardown Summary' -Type Header
    Write-Host "Objects removed: $removedCount" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Warning "Failures: $errorCount. Inspect the results object with -PassThru."
    }

    if ($PassThru) { return $results }
}
