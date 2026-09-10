function New-EntraUser {
    <#
    .SYNOPSIS
        Creates the seeded users defined in Data\EntraUsers.csv

    .DESCRIPTION
        Creates around three hundred cloud users: a hand-designed core chosen to be awkward in
        ways that break scripts, and bulk volume mapped from ADTestEnvironment so the same
        people exist in both labs. The rationale for each core row is in the Purpose column and
        in the module README.

        Everything is sent through Graph's $batch endpoint in chunks of twenty. At this volume
        the difference is not cosmetic: three hundred users take four calls' worth of round
        trips per phase rather than three hundred, and the whole step runs in well under a
        minute instead of a quarter of an hour.

        The work is done in four phases, and the ordering of the last three is forced:

        1. Create the users.
        2. Write the seed tag. This cannot go in the create call - Graph rejects
           onPremisesExtensionAttributes on POST /users and accepts it on PATCH, which is
           undocumented and consistent.
        3. Set managers, once every user exists, because the CSV names managers by key and a
           manager can appear below their reports in the file.
        4. Place every user in the Users administrative unit, which is what teardown treats as
           proof of ownership.

        Passwords are generated, used once, and never returned or stored. Nothing is expected
        to sign in as these accounts. forceChangePasswordNextSignIn is deliberately false: an
        account that must change its password at first sign-in cannot be used
        non-interactively by anything, which defeats the point of seeding it.

    .PARAMETER UserKey
        Creates only the named users, by their Key column. Defaults to all of them.

    .PARAMETER Tier
        Creates only Core rows (the designed edge cases) or only Bulk rows (the volume).
        Defaults to both.

    .PARAMETER SkipManagers
        Creates the users but not the manager relationships between them

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created users

    .OUTPUTS
        EntraUser[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraUser

        DESCRIPTION: Creates every seeded user and their manager chain
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment

    .EXAMPLE
        PS> New-EntraUser -Tier Core -PassThru

        DESCRIPTION: Creates only the nine designed edge-case users
        OUTPUT: The created user objects
        USE CASE: A fast rebuild when the volume is not what you are testing

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraUser')]
    param(
        [Parameter()]
        [string[]]$UserKey,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$SkipManagers,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraUsers')
    if ($Tier) { $definitions = @($definitions | Where-Object { $Tier -contains $_.Tier }) }
    if ($UserKey) {
        $definitions = @($definitions | Where-Object { $UserKey -contains $_.Key })
        $missing = @($UserKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for user key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    Write-Verbose "Creating $($definitions.Count) user(s)"

    # --- Phase 1: create ---------------------------------------------------------------
    $createRequests = [System.Collections.Generic.List[object]]::new()
    $definitionByKey = @{}

    foreach ($definition in $definitions) {
        $upn = '{0}{1}@{2}' -f $marker.Prefix, $definition.Key, $marker.UpnSuffix
        $definitionByKey[$definition.Key] = $definition

        # ShouldProcess is asked per object even though the send is batched, so -WhatIf still
        # names every user and -Confirm can still decline one.
        if (-not $PSCmdlet.ShouldProcess($upn, 'Create user')) { continue }

        $body = @{
            accountEnabled    = [bool]::Parse($definition.AccountEnabled)

            # The one object that does NOT take the seed prefix on its name. Seeded people carry
            # real names on purpose: the same person exists in the AD lab, and matching them by
            # display name is what makes hybrid identity testable. Prefixing here broke that for
            # no gain, because a user's ownership is proved by the administrative unit holding
            # it and by the prefix still present on its UPN - neither of which a human reads.
            displayName       = $definition.DisplayName
            mailNickname      = ('{0}{1}' -f $marker.Prefix, $definition.Key) -replace '[^A-Za-z0-9]', ''
            userPrincipalName = $upn
            passwordProfile   = @{
                forceChangePasswordNextSignIn = $false
                password                      = New-TestPassword
            }
        }

        # Only send optional properties that carry a value. Sending an empty string is not the
        # same as omitting it - Entra stores the empty string, and 'set to nothing' then looks
        # different from 'never set' to anything reading the directory afterwards.
        if ($definition.GivenName) { $body.givenName = $definition.GivenName }
        if ($definition.Surname) { $body.surname = $definition.Surname }
        if ($definition.Department) { $body.department = $definition.Department }
        if ($definition.JobTitle) { $body.jobTitle = $definition.JobTitle }
        if ($definition.EmployeeId) { $body.employeeId = $definition.EmployeeId }
        if ($definition.EmployeeType) { $body.employeeType = $definition.EmployeeType }

        # Owen deliberately has none. Entra accepts the user and then refuses every licence
        # assignment for it, which is the most common licensing failure there is.
        if ($definition.UsageLocation) { $body.usageLocation = $definition.UsageLocation }

        $createRequests.Add([PSCustomObject]@{
                Reference = $definition.Key
                Method    = 'POST'
                Url       = '/users'
                Body      = $body
            })
    }

    if ($createRequests.Count -eq 0) {
        Write-TestProgress -Activity 'Seeding users' -Completed -ShowProgress:$ShowProgress
        return
    }

    $createResults = @(Invoke-EntraBatch -Request $createRequests -Connection $connection `
            -Activity 'Seeding users' -ShowProgress:$ShowProgress)

    $idByKey = @{}
    foreach ($result in $createResults) {
        if ($result.Success -and $result.Body.id) { $idByKey[$result.Reference] = $result.Body.id }
        else { Write-Warning "Could not create user '$($result.Reference)': $($result.Error)" }
    }
    Write-Verbose "Created $($idByKey.Count) of $($createRequests.Count) user(s)"

    # --- Phase 2: seed tag -------------------------------------------------------------
    # Separate because Graph rejects onPremisesExtensionAttributes on POST /users.
    if ($idByKey.Count -gt 0) {
        $tagRequests = foreach ($key in $idByKey.Keys) {
            [PSCustomObject]@{
                Reference = $key
                Method    = 'PATCH'
                Url       = "/users/$($idByKey[$key])"
                Body      = @{
                    onPremisesExtensionAttributes = @{ extensionAttribute15 = $marker.Tag }
                    companyName                   = $marker.Tag
                }
            }
        }

        $tagResults = @(Invoke-EntraBatch -Request @($tagRequests) -Connection $connection `
                -Activity 'Tagging users' -ShowProgress:$ShowProgress)
        $untagged = @($tagResults | Where-Object { -not $_.Success })
        if ($untagged.Count -gt 0) {
            Write-Warning ("$($untagged.Count) user(s) were created but could not be tagged. They remain " +
                "identifiable by their prefixed UPN and their administrative unit, so teardown will still find them.")
        }
    }

    # --- Phase 3: managers -------------------------------------------------------------
    if (-not $SkipManagers -and $idByKey.Count -gt 0) {
        $managerRequests = [System.Collections.Generic.List[object]]::new()

        foreach ($key in $idByKey.Keys) {
            $definition = $definitionByKey[$key]
            if (-not $definition.Manager) { continue }

            if (-not $idByKey.ContainsKey($definition.Manager)) {
                Write-Verbose "User '$key' names manager '$($definition.Manager)', which was not created in this run."
                continue
            }

            $managerRequests.Add([PSCustomObject]@{
                    Reference = $key
                    Method    = 'PUT'
                    Url       = "/users/$($idByKey[$key])/manager/`$ref"
                    Body      = @{ '@odata.id' = "$($connection.GraphBaseUri)/v1.0/users/$($idByKey[$definition.Manager])" }
                })
        }

        if ($managerRequests.Count -gt 0) {
            $managerResults = @(Invoke-EntraBatch -Request $managerRequests.ToArray() -Connection $connection `
                    -Activity 'Setting managers' -ShowProgress:$ShowProgress)
            $failed = @($managerResults | Where-Object { -not $_.Success })
            if ($failed.Count -gt 0) {
                Write-Warning "$($failed.Count) manager relationship(s) could not be set. First error: $($failed[0].Error)"
            }
            Write-Verbose "Set $(@($managerResults | Where-Object Success).Count) manager relationship(s)"
        }
    }

    # --- Phase 4: containment ----------------------------------------------------------
    if ($idByKey.Count -gt 0) {
        $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
            Where-Object { $_.displayName -eq ('{0}Users' -f $marker.Prefix) } | Select-Object -First 1

        if ($unit) {
            $placed = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($idByKey.Values) -Connection $connection `
                -Activity 'Placing users in their administrative unit' -ShowProgress:$ShowProgress
            Write-Verbose "Placed $placed user(s) in '$($unit.displayName)'"
        }
        else {
            Write-Warning ("No $($marker.Prefix)Users administrative unit exists, so the created users are not " +
                "contained. Teardown will fall back to matching on the prefixed UPN. Run " +
                "New-EntraAdministrativeUnit first.")
        }
    }

    Write-TestProgress -Activity 'Seeding users' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) {
        return @(foreach ($key in $idByKey.Keys) {
                $definition = $definitionByKey[$key]
                [PSCustomObject]@{
                    PSTypeName        = 'EntraUser'
                    Key               = $key
                    Id                = $idByKey[$key]
                    DisplayName       = $definition.DisplayName
                    UserPrincipalName = '{0}{1}@{2}' -f $marker.Prefix, $key, $marker.UpnSuffix
                    Department        = $definition.Department
                    AccountEnabled    = [bool]::Parse($definition.AccountEnabled)
                    UsageLocation     = $definition.UsageLocation
                    Tier              = $definition.Tier
                    Purpose           = $definition.Purpose
                }
            })
    }
}
