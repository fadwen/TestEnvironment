function New-EntraApplication {
    <#
    .SYNOPSIS
        Creates the seeded app registrations, their service principals and their assignments

    .DESCRIPTION
        Users and groups answer who exists. Applications are what turn that into who has
        access to what, which is the question most scripts written against Entra are actually
        trying to report on, and the one that is not reproducible without them.

        Six applications are created, and the interesting ones are the middle three. One app
        is assigned to a group only, one to a user only, and one to both a group and a user
        who is already in that group. That last pair is the most common access-review bug
        there is: Marcus is assigned to the Payroll Console directly and belongs to no group
        that has it, so a report that expands group assignments and stops there misses him
        entirely, while Priya is assigned both ways and gets counted twice by a naive union.

        The application and the service principal are deliberately kept distinct, including
        one application created with no service principal at all. They are two objects and
        people conflate them constantly - the registration is the definition, the service
        principal is the instance of it in this tenant that assignments and sign-ins actually
        attach to. An app with no service principal cannot be signed into and does not appear
        in enterprise applications, which is exactly what it looks like when consent has
        never been granted.

        Creating the service principal is retried, because it fails on first attempt more
        often than not. Verified against a live tenant: POST /servicePrincipals for an
        application created moments earlier returns "The appId does not reference a valid
        application object" - which reads like a wrong id and is really replication lag.

        App role assignments use the default access role, an all-zero GUID. That is how Entra
        represents "assigned to the application without a specific role" and it is what the
        portal creates when an app defines no roles of its own.

    .PARAMETER ApplicationKey
        Creates only the named applications, by their Key column. Defaults to all of them.

    .PARAMETER SkipAssignment
        Creates the applications and service principals but assigns nobody

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created applications

    .OUTPUTS
        EntraApplication[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraApplication

        DESCRIPTION: Creates all six applications, five service principals and their assignments
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment

    .EXAMPLE
        PS> New-EntraApplication -ApplicationKey app-direct-only -PassThru

        DESCRIPTION: Creates just the application with a direct assignee and no group
        OUTPUT: The application object
        USE CASE: Reproducing the access report that misses directly-assigned users

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraApplication')]
    param(
        [Parameter()]
        [string[]]$ApplicationKey,

        [Parameter()]
        [switch]$SkipAssignment,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraApplications')
    if ($ApplicationKey) {
        $definitions = @($definitions | Where-Object { $ApplicationKey -contains $_.Key })
        $missing = @($ApplicationKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for application key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    # The all-zero GUID is Entra's "default access" app role: assigned to the application,
    # but to no role it defines. It is what the portal writes for an app with no app roles.
    $defaultAccessRoleId = '00000000-0000-0000-0000-000000000000'

    # Entra places no uniqueness constraint on an application's displayName, so without this a
    # re-run creates a second registration - and a second service principal - for each one.
    $existingByName = @{}
    foreach ($application in (Get-EntraSeededObject -Type Applications -Connection $connection)) {
        $existingByName[$application.displayName] = $application
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $cache = @{}
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName

        Write-TestProgress -Activity 'Seeding applications' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        if ($existingByName.ContainsKey($displayName)) {
            Write-Verbose "Application '$displayName' already exists; reusing it"
            $existingApp = $existingByName[$displayName]
            $existingPrincipal = $null
            try {
                $existingPrincipal = @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $connection `
                        -Paginate -ConsistencyLevel -Query @{ '$filter' = "appId eq '$($existingApp.appId)'"; '$select' = 'id' }) |
                    Select-Object -First 1
            }
            catch {
                Write-Verbose "Could not look up the service principal for '$displayName': $($_.Exception.Message)"
            }

            $created.Add([PSCustomObject]@{
                    PSTypeName         = 'EntraApplication'
                    Key                = $definition.Key
                    Id                 = $existingApp.id
                    AppId              = $existingApp.appId
                    ServicePrincipalId = $existingPrincipal.id
                    DisplayName        = $displayName
                    Tags               = @($existingApp.tags)
                    Assignments        = @($definition.AppRoleAssignments -split ';' | Where-Object { $_ })
                    Purpose            = $definition.Purpose
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create application')) { continue }

        # tags is the ownership marker for applications, and unlike the user seed tag it is
        # both writable at create time and returned on read. The extra tags from the CSV are
        # appended, so HideApp works without displacing the marker.
        $tags = @($marker.Tag) + @($definition.Tags -split ';' | Where-Object { $_ })

        $body = @{
            displayName    = $displayName
            signInAudience = $definition.SignInAudience
            tags           = $tags
            notes          = $marker.Description
        }

        # Reply URLs are the nearest thing Entra has to Okta's trusted origins, and the two
        # collections are not interchangeable: a URL under `web` is a redirect target for a
        # confidential client, while one under `spa` additionally makes Entra emit the CORS
        # headers a browser needs for the token request. Putting a single-page app's URL in
        # `web` produces an app that redirects correctly and then fails at the token call.
        $webUris = @($definition.WebRedirectUris -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        $spaUris = @($definition.SpaRedirectUris -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })

        if ($webUris) { $body.web = @{ redirectUris = $webUris; homePageUrl = $webUris[0] } }
        if ($spaUris) { $body.spa = @{ redirectUris = $spaUris } }

        try {
            $application = Invoke-EntraRequest -Method POST -Path '/applications' -Body $body
        }
        catch {
            Write-Error "Failed to create application '${displayName}': $($_.Exception.Message)"
            continue
        }

        $servicePrincipalId = $null
        if ([bool]::Parse($definition.CreateServicePrincipal)) {
            try {
                # This is the call that loses the race with replication most reliably of any
                # in the module, and it does so as a 400 rather than a 404 - Graph says the
                # appId "does not reference a valid application object" about an application
                # it created moments earlier. Status code alone cannot distinguish that from
                # a genuinely bad request, so the retry matches the message.
                $servicePrincipal = Invoke-EntraRequest -Method POST -Path '/servicePrincipals' `
                    -RetryOnNotFound -RetryOnErrorMatch 'does not reference a valid application object' -Body @{
                    appId = $application.appId
                    tags  = $tags
                }
                $servicePrincipalId = $servicePrincipal.id
                Write-Verbose "Created service principal for '$displayName' ($servicePrincipalId)"
            }
            catch {
                Write-Warning ("Created application '$displayName' but its service principal failed: " +
                    "$($_.Exception.Message). Nothing can be assigned to it until one exists.")
            }
        }

        if (-not $SkipAssignment -and $servicePrincipalId -and $definition.AppRoleAssignments) {
            foreach ($key in ($definition.AppRoleAssignments -split ';' | Where-Object { $_ })) {
                $key = $key.Trim()

                # The CSV does not say whether an assignee is a user or a group, because the
                # keys are already unique across both files. Groups are tried first: the
                # group seed file is the smaller lookup and a group key never collides with
                # a user key.
                $principalId = Resolve-EntraSeededId -Key $key -Kind Group -Cache $cache -Connection $connection
                if (-not $principalId) {
                    $principalId = Resolve-EntraSeededId -Key $key -Kind User -Cache $cache -Connection $connection
                }
                if (-not $principalId) {
                    Write-Warning ("Application '$($definition.Key)' assigns '$key', which matches no seeded user " +
                        "or group. Skipping it.")
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess($displayName, "Assign $key")) { continue }

                try {
                    Invoke-EntraRequest -Method POST -Path "/servicePrincipals/$servicePrincipalId/appRoleAssignedTo" -RetryOnNotFound -Body @{
                        principalId = $principalId
                        resourceId  = $servicePrincipalId
                        appRoleId   = $defaultAccessRoleId
                    } | Out-Null
                    Write-Verbose "Assigned '$key' to '$displayName'"
                }
                catch {
                    if ($_.Exception.Message -match 'already exist|Permission being assigned already exists') {
                        Write-Verbose "'$key' is already assigned to '$displayName'"
                    }
                    else {
                        Write-Warning "Could not assign '$key' to '$displayName': $($_.Exception.Message)"
                    }
                }
            }
        }

        $created.Add([PSCustomObject]@{
                PSTypeName         = 'EntraApplication'
                Key                = $definition.Key
                Id                 = $application.id
                AppId              = $application.appId
                ServicePrincipalId = $servicePrincipalId
                DisplayName        = $displayName
                Tags               = $tags
                Assignments        = @($definition.AppRoleAssignments -split ';' | Where-Object { $_ })
                Purpose            = $definition.Purpose
            })

        Write-Verbose "Created application '$displayName' ($($application.id))"
    }

    # Applications go in an administrative unit like everything else. Their service principals
    # cannot - Graph accepts only users, groups, devices and applications as unit members - so
    # those stay identified by the name prefix and their seed tag.
    if ($created.Count -gt 0) {
        $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
            Where-Object { $_.displayName -eq ('{0}Applications' -f $marker.Prefix) } | Select-Object -First 1

        if ($unit) {
            $placed = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($created.Id) -Connection $connection `
                -Activity 'Placing applications in their administrative unit' -ShowProgress:$ShowProgress
            Write-Verbose "Placed $placed application(s) in '$($unit.displayName)'"
        }
        else {
            Write-Warning ("No $($marker.Prefix)Applications administrative unit exists, so the created " +
                "applications are not contained. Run New-EntraAdministrativeUnit first.")
        }
    }

    Write-TestProgress -Activity 'Seeding applications' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
