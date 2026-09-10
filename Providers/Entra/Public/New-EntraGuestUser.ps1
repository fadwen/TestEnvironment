function New-EntraGuestUser {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the external identities defined in Data\EntraGuestUsers.csv
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraGuestUser')]
    param(
        [Parameter()]
        [string[]]$GuestKey,

        [Parameter()]
        [switch]$SkipGroups,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraGuestUsers')
    if ($GuestKey) {
        $definitions = @($definitions | Where-Object { $GuestKey -contains $_.Key })
        $missing = @($GuestKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for guest key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    Write-Verbose "Creating $($definitions.Count) external identity/identities"

    $created = [System.Collections.Generic.List[object]]::new()
    $idByKey = @{}
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        Write-TestProgress -Activity 'Seeding external identities' -Status $definition.DisplayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        $email = $definition.InvitedEmail -replace '\{Prefix\}', $marker.Prefix
        $isInvited = $definition.CreationMethod -eq 'Invitation'

        # The identifier a human would recognise, used for ShouldProcess and for every message
        # below. For an invited guest the UPN does not exist until Entra mints it.
        $target = if ($isInvited) { $email } else { '{0}{1}@{2}' -f $marker.Prefix, $definition.Key, $marker.UpnSuffix }

        # --- Already there? ------------------------------------------------------------
        $existingId = $null
        try {
            if ($isInvited) {
                $literal = $email.Replace("'", "''")
                $found = @(Invoke-EntraRequest -Method GET -Path '/users' -Connection $connection -Paginate -ConsistencyLevel `
                        -Query @{ '$filter' = "mail eq '$literal'"; '$select' = 'id,userPrincipalName' })
                if ($found.Count -ge 1) { $existingId = $found[0].id }
            }
            else {
                $found = Invoke-EntraRequest -Method GET -Connection $connection `
                    -Path "/users/$([uri]::EscapeDataString($target))" -Query @{ '$select' = 'id' }
                $existingId = $found.id
            }
        }
        catch {
            # A 404 on the direct address is the ordinary "not there yet" answer, not a fault.
            Write-Verbose "No existing identity for '$target': $($_.Exception.Message)"
        }

        if ($existingId) {
            Write-Verbose "External identity '$target' already exists ($existingId)"
            $idByKey[$definition.Key] = $existingId
            $created.Add([PSCustomObject]@{
                    PSTypeName  = 'EntraGuestUser'
                    Key         = $definition.Key
                    Id          = $existingId
                    DisplayName = $definition.DisplayName
                    Method      = $definition.CreationMethod
                    UserType    = $definition.UserType
                    InvitedMail = if ($isInvited) { $email } else { $null }
                    Purpose     = $definition.Purpose
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($target, "Create external identity ($($definition.CreationMethod))")) { continue }

        # --- Create --------------------------------------------------------------------
        $newId = $null

        if ($isInvited) {
            try {
                # invitedUserType is set on the invitation rather than PATCHed afterwards. The
                # end state is identical to inviting a guest and converting it, and doing it in
                # one call means there is no window where the row is half-applied.
                $invitation = Invoke-EntraRequest -Method POST -Path '/invitations' -Connection $connection -Body @{
                    invitedUserEmailAddress = $email
                    invitedUserDisplayName  = $definition.DisplayName
                    invitedUserType         = $definition.UserType
                    inviteRedirectUrl       = 'https://example.com/entralab/redeem'

                    # Not a parameter, deliberately. See the description: there is no way to
                    # make this module send mail.
                    sendInvitationMessage   = $false
                }
                $newId = $invitation.invitedUser.id
            }
            catch {
                $message = $_.Exception.Message

                # Verified live against a tenant whose allowInvitesFrom is adminsAndGuestInviters.
                # Graph answers 403 "Guest invitations not allowed for your company", which names
                # neither the cause nor the fix, and two plausible readings of it are both wrong:
                #
                #   - It is not User.ReadWrite.All missing. That was granted and consented, and
                #     appeared in the token's roles claim, and the invitation was still refused.
                #   - It is not the Guest Inviter directory role missing either. Assigning it and
                #     re-acquiring the token so the role appeared in wids changed nothing.
                #
                # What is left is User.Invite.All, the permission built for this, which the seed
                # app requests as optional. So the message points there rather than at the tenant
                # setting - the setting is the gate, but the permission is what opens it.
                if ($message -match 'Guest invitations not allowed') {
                    Write-Warning ("Could not invite '$email': this tenant restricts who may invite guests " +
                        '(see allowInvitesFrom on /policies/authorizationPolicy) and this application is not ' +
                        'permitted. Grant it User.Invite.All - verified insufficient are User.ReadWrite.All ' +
                        'alone and the Guest Inviter directory role - or skip the step with -Skip GuestUsers.')
                    continue
                }

                Write-Warning "Could not invite '$email': $message"
                continue
            }
        }
        else {
            try {
                $user = Invoke-EntraRequest -Method POST -Path '/users' -Connection $connection -Body @{
                    accountEnabled    = $true
                    displayName       = $definition.DisplayName
                    mailNickname      = ('{0}{1}' -f $marker.Prefix, $definition.Key) -replace '[^A-Za-z0-9]', ''
                    userPrincipalName = $target

                    # The whole point of this row: userType is just a property on an otherwise
                    # ordinary cloud account. Nothing about the UPN or the mail says external.
                    userType          = $definition.UserType
                    passwordProfile   = @{
                        forceChangePasswordNextSignIn = $false
                        password                      = New-TestPassword
                    }
                }
                $newId = $user.id
            }
            catch {
                Write-Warning "Could not create '$target': $($_.Exception.Message)"
                continue
            }
        }

        if (-not $newId) { continue }
        $idByKey[$definition.Key] = $newId

        # --- Attributes and the seed tag -----------------------------------------------
        # Separate from the create for the same reason ordinary users are: Graph rejects
        # onPremisesExtensionAttributes on POST /users, and the invitation endpoint accepts no
        # directory attributes at all beyond the display name.
        $patch = @{
            onPremisesExtensionAttributes = @{ extensionAttribute15 = $marker.Tag }
            companyName                   = $marker.Tag
        }
        if ($definition.GivenName) { $patch.givenName = $definition.GivenName }
        if ($definition.Surname) { $patch.surname = $definition.Surname }
        if ($definition.Department) { $patch.department = $definition.Department }
        if ($definition.JobTitle) { $patch.jobTitle = $definition.JobTitle }

        # Left unset on two rows on purpose. A guest with no usageLocation is the default state
        # of every invitation, and it is the state in which every licence assignment fails.
        if ($definition.UsageLocation) { $patch.usageLocation = $definition.UsageLocation }

        try {
            Invoke-EntraRequest -Method PATCH -Path "/users/$newId" -Body $patch -RetryOnNotFound -Connection $connection | Out-Null
        }
        catch {
            Write-Warning ("Created '$target' but could not write its attributes: $($_.Exception.Message). " +
                'It remains identifiable by its prefixed UPN and its administrative unit.')
        }

        $created.Add([PSCustomObject]@{
                PSTypeName  = 'EntraGuestUser'
                Key         = $definition.Key
                Id          = $newId
                DisplayName = $definition.DisplayName
                Method      = $definition.CreationMethod
                UserType    = $definition.UserType
                InvitedMail = if ($isInvited) { $email } else { $null }
                Purpose     = $definition.Purpose
            })

        Write-Verbose "Created external identity '$($definition.DisplayName)' ($newId)"
    }

    # --- Group membership --------------------------------------------------------------
    if (-not $SkipGroups -and $idByKey.Count -gt 0) {
        $groupCache = @{}
        $memberRequests = [System.Collections.Generic.List[object]]::new()

        foreach ($definition in $definitions) {
            if (-not $definition.Groups -or -not $idByKey.ContainsKey($definition.Key)) { continue }

            foreach ($groupKey in @($definition.Groups -split ';' | Where-Object { $_ })) {
                $groupId = Resolve-EntraSeededId -Key $groupKey.Trim() -Kind Group -Cache $groupCache -Connection $connection
                if (-not $groupId) {
                    Write-Warning "Guest '$($definition.Key)' names group '$groupKey', which does not exist. Skipping it."
                    continue
                }

                $memberRequests.Add([PSCustomObject]@{
                        Reference = "$($definition.Key)->$groupKey"
                        Method    = 'POST'
                        Url       = "/groups/$groupId/members/`$ref"
                        Body      = @{ '@odata.id' = "$($connection.GraphBaseUri)/v1.0/directoryObjects/$($idByKey[$definition.Key])" }
                    })
            }
        }

        if ($memberRequests.Count -gt 0) {
            $memberResults = @(Invoke-EntraBatch -Request $memberRequests.ToArray() -Connection $connection `
                    -Activity 'Adding external identities to groups' -ShowProgress:$ShowProgress)

            # The same three wordings Add-EntraUnitMember and New-EntraGroup match on. Graph
            # phrases a duplicate differently depending on the collection, and all three mean
            # the membership is already there - which is the ordinary answer on a re-run.
            $duplicate = 'already exist|added object references already exist|A conflicting object'

            foreach ($result in ($memberResults | Where-Object { -not $_.Success })) {
                if ($result.Error -match $duplicate) {
                    Write-Verbose "Membership $($result.Reference) already existed"
                    continue
                }
                Write-Warning "Could not add $($result.Reference): $($result.Error)"
            }
        }
    }

    # --- Containment -------------------------------------------------------------------
    if ($idByKey.Count -gt 0) {
        $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
            Where-Object { $_.displayName -eq ('{0}Users' -f $marker.Prefix) } | Select-Object -First 1

        if ($unit) {
            $placed = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($idByKey.Values) -Connection $connection `
                -Activity 'Placing external identities in their administrative unit' -ShowProgress:$ShowProgress
            Write-Verbose "Placed $placed external identity/identities in '$($unit.displayName)'"
        }
        else {
            Write-Warning ("No $($marker.Prefix)Users administrative unit exists, so the external identities are " +
                'not contained. Run New-EntraAdministrativeUnit first.')
        }
    }

    Write-TestProgress -Activity 'Seeding external identities' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
