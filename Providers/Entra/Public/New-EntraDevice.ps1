function New-EntraDevice {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded device objects defined in Data\EntraDevices.csv
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraDevice')]
    param(
        [Parameter()]
        [string[]]$DeviceKey,

        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$SkipOwners,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraDevices')
    if ($Tier) { $definitions = @($definitions | Where-Object { $Tier -contains $_.Tier }) }
    if ($DeviceKey) {
        $definitions = @($definitions | Where-Object { $DeviceKey -contains $_.Key })
        $missing = @($DeviceKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for device key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    Write-Verbose "Creating $($definitions.Count) device(s)"

    # --- Phase 1: create ---------------------------------------------------------------
    $createRequests = [System.Collections.Generic.List[object]]::new()
    $definitionByKey = @{}

    foreach ($definition in $definitions) {
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName
        $definitionByKey[$definition.Key] = $definition

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create device')) { continue }

        # The alternative security identifier is required and its key must be base64. The
        # content is arbitrary for a device that will never authenticate, so it carries the
        # seed marker - not a proof of ownership, since Graph will not filter on it, but it
        # does let an operator inspecting the raw object see where it came from.
        $securityIdentity = [Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes("$($marker.Tag):$($definition.Key)"))

        $createRequests.Add([PSCustomObject]@{
                Reference = $definition.Key
                Method    = 'POST'
                Url       = '/devices'
                Body      = @{
                    displayName            = $displayName
                    deviceId               = [guid]::NewGuid().ToString()
                    operatingSystem        = $definition.OperatingSystem
                    operatingSystemVersion = $definition.OperatingSystemVersion
                    accountEnabled         = [bool]::Parse($definition.AccountEnabled)
                    isCompliant            = [bool]::Parse($definition.IsCompliant)
                    isManaged              = [bool]::Parse($definition.IsManaged)
                    alternativeSecurityIds = @(@{ type = 2; key = $securityIdentity })
                }
            })
    }

    if ($createRequests.Count -eq 0) {
        Write-TestProgress -Activity 'Seeding devices' -Completed -ShowProgress:$ShowProgress
        return
    }

    $createResults = @(Invoke-EntraBatch -Request $createRequests.ToArray() -Connection $connection `
            -Activity 'Seeding devices' -ShowProgress:$ShowProgress)

    $idByKey = @{}
    foreach ($result in $createResults) {
        if ($result.Success -and $result.Body.id) { $idByKey[$result.Reference] = $result.Body.id }
        else { Write-Warning "Could not create device '$($result.Reference)': $($result.Error)" }
    }
    Write-Verbose "Created $($idByKey.Count) of $($createRequests.Count) device(s)"

    # --- Phase 2: registered owners ----------------------------------------------------
    if (-not $SkipOwners -and $idByKey.Count -gt 0) {
        $userIdByKey = @{}
        foreach ($user in (Get-EntraSeededObject -Type Users -Connection $connection)) {
            if ($user.userPrincipalName -match "^$([regex]::Escape($marker.Prefix))(?<key>.+?)@") {
                $userIdByKey[$Matches['key']] = $user.id
            }
        }

        $ownerRequests = [System.Collections.Generic.List[object]]::new()
        $missingOwners = 0

        foreach ($key in $idByKey.Keys) {
            $owner = $definitionByKey[$key].RegisteredOwner
            if (-not $owner) { continue }
            if (-not $userIdByKey.ContainsKey($owner)) { $missingOwners++; continue }

            $ownerRequests.Add([PSCustomObject]@{
                    Reference = $key
                    Method    = 'POST'
                    Url       = "/devices/$($idByKey[$key])/registeredOwners/`$ref"
                    Body      = @{ '@odata.id' = "$($connection.GraphBaseUri)/v1.0/directoryObjects/$($userIdByKey[$owner])" }
                })
        }

        if ($missingOwners -gt 0) {
            Write-Warning "$missingOwners device(s) named an owner that does not exist and were left unowned."
        }

        if ($ownerRequests.Count -gt 0) {
            # -RetryOnNotFound because a device is reliably not addressable for its owner
            # reference for a few seconds after the create returns.
            $ownerResults = @(Invoke-EntraBatch -Request $ownerRequests.ToArray() -Connection $connection `
                    -RetryOnNotFound -Activity 'Assigning device owners' -ShowProgress:$ShowProgress)

            $duplicate = 'already exist|added object references already exist|A conflicting object'
            $failed = @($ownerResults | Where-Object { -not $_.Success -and $_.Error -notmatch $duplicate })
            if ($failed.Count -gt 0) {
                Write-Warning "$($failed.Count) device owner(s) could not be set. First error: $($failed[0].Error)"
            }
            Write-Verbose "Set $(@($ownerResults | Where-Object Success).Count) device owner(s)"
        }
    }

    # --- Phase 3: containment ----------------------------------------------------------
    if ($idByKey.Count -gt 0) {
        $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
            Where-Object { $_.displayName -eq ('{0}Devices' -f $marker.Prefix) } | Select-Object -First 1

        if ($unit) {
            $placed = Add-EntraUnitMember -UnitId $unit.id -ObjectId @($idByKey.Values) -Connection $connection `
                -Activity 'Placing devices in their administrative unit' -ShowProgress:$ShowProgress
            Write-Verbose "Placed $placed device(s) in '$($unit.displayName)'"
        }
        else {
            Write-Warning ("No $($marker.Prefix)Devices administrative unit exists, so the created devices are not " +
                "contained. Run New-EntraAdministrativeUnit first.")
        }
    }

    Write-TestProgress -Activity 'Seeding devices' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) {
        return @(foreach ($key in $idByKey.Keys) {
                $definition = $definitionByKey[$key]
                [PSCustomObject]@{
                    PSTypeName      = 'EntraDevice'
                    Key             = $key
                    Id              = $idByKey[$key]
                    DisplayName     = '{0}{1}' -f $marker.Prefix, $definition.DisplayName
                    OperatingSystem = $definition.OperatingSystem
                    IsCompliant     = [bool]::Parse($definition.IsCompliant)
                    IsManaged       = [bool]::Parse($definition.IsManaged)
                    AccountEnabled  = [bool]::Parse($definition.AccountEnabled)
                    RegisteredOwner = $definition.RegisteredOwner
                    Tier            = $definition.Tier
                    Purpose         = $definition.Purpose
                }
            })
    }
}
