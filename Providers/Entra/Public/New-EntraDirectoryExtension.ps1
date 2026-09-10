function New-EntraDirectoryExtension {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates custom directory extension attributes and populates them
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraDirectoryExtension')]
    param(
        [Parameter()]
        [string[]]$ExtensionKey,

        [Parameter()]
        [switch]$SkipValues,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraDirectoryExtensions')
    if ($ExtensionKey) {
        $definitions = @($definitions | Where-Object { $ExtensionKey -contains $_.Key })
        $missing = @($ExtensionKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for extension key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    # --- The schema application --------------------------------------------------------
    # Extensions belong to an application, and a dedicated one keeps them together: deleting
    # it removes every attribute and every value at once, which is what makes teardown of a
    # schema change a single operation rather than ten.
    $schemaAppName = '{0}Schema' -f $marker.Prefix
    $schemaApp = @(Get-EntraSeededObject -Type Applications -Connection $connection) |
        Where-Object { $_.displayName -eq $schemaAppName } | Select-Object -First 1

    if (-not $schemaApp) {
        if (-not $PSCmdlet.ShouldProcess($schemaAppName, 'Create schema application')) { return }

        try {
            $created = Invoke-EntraRequest -Method POST -Path '/applications' -Connection $connection -Body @{
                displayName    = $schemaAppName
                signInAudience = 'AzureADMyOrg'
                tags           = @($marker.Tag)
                notes          = "Owns the seeded directory extension attributes. $($marker.Description)"
            }
            $schemaApp = $created
            Write-Verbose "Created schema application '$schemaAppName' ($($created.id))"

            # Waited for deliberately, and this is not belt and braces. An extension property
            # POSTed against an application that has not finished materialising is *accepted*
            # and then silently discarded: a first run reported eight extensions created and
            # left exactly one behind. Reading the application back until it answers is the
            # only reliable signal that it is ready to own anything.
            $ready = $false
            foreach ($delay in 5, 5, 10, 15, 20) {
                Start-Sleep -Seconds $delay
                try {
                    $null = Invoke-EntraRequest -Method GET -Path "/applications/$($created.id)" `
                        -Query @{ '$select' = 'id' } -Connection $connection
                    $ready = $true
                    break
                }
                catch {
                    Write-Verbose "Schema application not readable yet: $($_.Exception.Message)"
                }
            }
            if (-not $ready) {
                Write-Warning ("The schema application was created but is not readable yet. Its extension " +
                    "attributes may not all be created; run this command again once the directory has settled.")
            }

            $unit = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection) |
                Where-Object { $_.displayName -eq ('{0}Applications' -f $marker.Prefix) } | Select-Object -First 1
            if ($unit) {
                Add-EntraUnitMember -UnitId $unit.id -ObjectId @($created.id) -Connection $connection `
                    -Activity 'Placing the schema application' | Out-Null
            }
        }
        catch {
            Write-Error "Failed to create the schema application '${schemaAppName}': $($_.Exception.Message)" -ErrorAction Stop
            return
        }
    }
    else {
        Write-Verbose "Reusing schema application '$schemaAppName' ($($schemaApp.id))"
    }

    # Checked on every run, not only when the application is created. An environment seeded
    # before this requirement was understood has the application and the definitions but no
    # service principal, and therefore attributes that can never be written to. Adding one
    # afterwards fixes it in place rather than requiring a rebuild.
    $existingPrincipals = @()
    try {
        $existingPrincipals = @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $connection `
                -Paginate -ConsistencyLevel -Query @{ '$filter' = "appId eq '$($schemaApp.appId)'"; '$select' = 'id' })
    }
    catch {
        Write-Verbose "Could not check for the schema application's service principal: $($_.Exception.Message)"
    }

    if ($existingPrincipals.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($schemaAppName, 'Create the service principal its extensions require')) {
            try {
                $principal = Invoke-EntraRequest -Method POST -Path '/servicePrincipals' -Connection $connection `
                    -RetryOnNotFound -RetryOnErrorMatch 'does not reference a valid application object' -Body @{
                    appId = $schemaApp.appId
                    tags  = @($marker.Tag)
                }
                Write-Verbose "Created the schema application's service principal ($($principal.id))"
                # Provisioning the attributes behind it is not instant once the principal
                # appears, so the availability poll below does the actual waiting.
                Start-Sleep -Seconds 15
            }
            catch {
                Write-Warning ("Could not create the schema application's service principal: " +
                    "$($_.Exception.Message). Extension attributes cannot be written to until one exists.")
            }
        }
    }

    # The namespaced property name is built from the appId with its dashes removed. Graph
    # returns it on create, but it is derived here too so the mapping is available for objects
    # created in an earlier run.
    $appIdCompact = ($schemaApp.appId -replace '-', '')

    # --- The attributes ----------------------------------------------------------------
    $created = [System.Collections.Generic.List[object]]::new()
    $existing = @()
    try {
        $existing = @(Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                -Path "/applications/$($schemaApp.id)/extensionProperties")
    }
    catch {
        Write-Verbose "Could not list existing extension properties: $($_.Exception.Message)"
    }

    $index = 0
    foreach ($definition in $definitions) {
        $index++
        $propertyName = 'extension_{0}_{1}' -f $appIdCompact, $definition.Name

        Write-TestProgress -Activity 'Seeding directory extensions' -Status $definition.Name `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        $already = $existing | Where-Object { $_.name -eq $propertyName } | Select-Object -First 1
        if ($already) {
            Write-Verbose "Extension '$($definition.Name)' already exists"
            $created.Add([PSCustomObject]@{
                    PSTypeName   = 'EntraDirectoryExtension'
                    Key          = $definition.Key
                    Id           = $already.id
                    Name         = $definition.Name
                    PropertyName = $propertyName
                    DataType     = $definition.DataType
                    TargetObject = $definition.TargetObject
                    Purpose      = $definition.Purpose
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($definition.Name, "Create $($definition.DataType) extension on $($definition.TargetObject)")) { continue }

        try {
            $property = Invoke-EntraRequest -Method POST -Connection $connection -RetryOnNotFound `
                -Path "/applications/$($schemaApp.id)/extensionProperties" -Body @{
                name          = $definition.Name
                dataType      = $definition.DataType
                targetObjects = @($definition.TargetObject)
            }
        }
        catch {
            Write-Error "Failed to create extension '$($definition.Name)': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName   = 'EntraDirectoryExtension'
                Key          = $definition.Key
                Id           = $property.id
                Name         = $definition.Name
                PropertyName = $property.name
                DataType     = $definition.DataType
                TargetObject = $definition.TargetObject
                Purpose      = $definition.Purpose
            })

        Write-Verbose "Created extension '$($property.name)'"
    }

    # --- Verify, because a create response is not proof -------------------------------
    # The POST returns 201 with a body for extensions that do not survive. The only way to
    # know what exists is to list them back, so anything missing is created again rather than
    # reported as present and then failing every value write that references it.
    if ($created.Count -gt 0 -and -not $WhatIfPreference) {
        foreach ($attempt in 1, 2, 3) {
            Start-Sleep -Seconds (5 * $attempt)

            $live = @{}
            try {
                foreach ($property in (Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                            -Path "/applications/$($schemaApp.id)/extensionProperties")) {
                    $live[$property.name] = $property
                }
            }
            catch {
                Write-Verbose "Could not list extension properties on attempt ${attempt}: $($_.Exception.Message)"
                continue
            }

            $absent = @($created | Where-Object { -not $live.ContainsKey($_.PropertyName) })
            if ($absent.Count -eq 0) {
                Write-Verbose "All $($created.Count) extension(s) confirmed present"
                break
            }

            Write-Verbose "$($absent.Count) extension(s) did not survive creation; creating them again (attempt $attempt)"
            foreach ($missingExtension in $absent) {
                $definition = $definitions | Where-Object { $_.Key -eq $missingExtension.Key } | Select-Object -First 1
                try {
                    $property = Invoke-EntraRequest -Method POST -Connection $connection -RetryOnNotFound `
                        -Path "/applications/$($schemaApp.id)/extensionProperties" -Body @{
                        name          = $definition.Name
                        dataType      = $definition.DataType
                        targetObjects = @($definition.TargetObject)
                    }
                    $missingExtension.Id = $property.id
                }
                catch {
                    Write-Verbose "Recreating '$($definition.Name)' failed: $($_.Exception.Message)"
                }
            }
        }

        # Whatever is still absent is dropped from the result, so the value-writing pass below
        # does not reference an attribute that does not exist and fail every object because
        # of it.
        $confirmed = @{}
        try {
            foreach ($property in (Invoke-EntraRequest -Method GET -Connection $connection -Paginate `
                        -Path "/applications/$($schemaApp.id)/extensionProperties")) {
                $confirmed[$property.name] = $true
            }
        }
        catch {
            Write-Warning "Could not confirm which extension properties exist: $($_.Exception.Message)"
        }

        if ($confirmed.Count -gt 0) {
            $lost = @($created | Where-Object { -not $confirmed.ContainsKey($_.PropertyName) })
            if ($lost.Count -gt 0) {
                Write-Warning ("$($lost.Count) extension attribute(s) could not be created and are excluded: " +
                    ($lost.Name -join ', '))
                $surviving = @($created | Where-Object { $confirmed.ContainsKey($_.PropertyName) })
                $created.Clear()
                foreach ($item in $surviving) { $created.Add($item) }
            }
        }
    }

    # --- Wait for the attributes to become usable --------------------------------------
    # Existing on the application and being writable on a user are two different states, and
    # the gap between them is minutes rather than seconds. Until an attribute appears in
    # getAvailableExtensionProperties, every PATCH naming it is rejected with "The following
    # extension properties are not available", which reads like the attribute is missing
    # rather than like it is still being provisioned.
    #
    # That endpoint is the authoritative answer, so it is polled rather than the application's
    # own list, which reports the attribute as present long before it can be used.
    if (-not $SkipValues -and $created.Count -gt 0 -and -not $WhatIfPreference) {
        $usable = @{}
        foreach ($delay in 10, 15, 20, 30, 30, 45) {
            try {
                $available = Invoke-EntraRequest -Method POST -Connection $connection `
                    -Path '/directoryObjects/getAvailableExtensionProperties' -Body @{ isSyncedFromOnPremises = $false }
                $usable = @{}
                foreach ($property in @($available.value)) { $usable[$property.name] = $true }
            }
            catch {
                Write-Verbose "Could not read available extension properties: $($_.Exception.Message)"
            }

            $waiting = @($created | Where-Object { -not $usable.ContainsKey($_.PropertyName) })
            if ($waiting.Count -eq 0) {
                Write-Verbose "All $($created.Count) extension(s) are available for use"
                break
            }

            Write-Verbose "$($waiting.Count) extension(s) not yet available; waiting ${delay}s"
            Start-Sleep -Seconds $delay
        }

        $unusable = @($created | Where-Object { -not $usable.ContainsKey($_.PropertyName) })
        if ($unusable.Count -gt 0) {
            Write-Warning ("$($unusable.Count) extension attribute(s) exist but are not yet available to write to: " +
                "$($unusable.Name -join ', '). The definitions are correct and Entra is still provisioning them. " +
                "Run New-EntraDirectoryExtension again in a few minutes to populate the values; it is idempotent.")

            # Excluded from this pass rather than attempted. One unavailable attribute in a
            # PATCH body fails the whole request, so leaving it in would cost the values of
            # every attribute that IS ready, on every object.
            $ready = @($created | Where-Object { $usable.ContainsKey($_.PropertyName) })
            $created.Clear()
            foreach ($item in $ready) { $created.Add($item) }
        }
    }

    # --- Values ------------------------------------------------------------------------
    if (-not $SkipValues -and $created.Count -gt 0) {
        $requests = [System.Collections.Generic.List[object]]::new()

        foreach ($target in 'User', 'Group', 'Device') {
            $applicable = @($created | Where-Object { $_.TargetObject -eq $target })
            if ($applicable.Count -eq 0) { continue }

            $type = switch ($target) { 'User' { 'Users' } 'Group' { 'Groups' } 'Device' { 'Devices' } }
            $objects = @(Get-EntraSeededObject -Type $type -Connection $connection)

            if ($target -eq 'Device') {
                # Windows only, and this is Entra's rule rather than a choice. Verified live:
                # a PATCH against a non-Windows device object is refused with "Properties
                # other than AccountEnabled and ExtensionAttribute1..15 can be modified only
                # on windows devices", so a directory extension is unwritable on the macOS,
                # iOS and Android devices this module seeds. They are filtered out here rather
                # than left to fail, because a failure per device would bury the real errors.
                $all = $objects.Count
                $objects = @($objects | Where-Object { $_.operatingSystem -eq 'Windows' })
                if ($all -ne $objects.Count) {
                    Write-Verbose ("Skipping extension values on $($all - $objects.Count) non-Windows device(s); " +
                        'Entra permits them only on Windows device objects.')
                }
            }

            if ($objects.Count -eq 0) { continue }

            # Core-only attributes go on the first few objects; the ones marked 'all' go
            # everywhere, so a query for them returns a realistic population rather than one row.
            $objectIndex = 0
            foreach ($object in $objects) {
                $objectIndex++
                $body = @{}

                foreach ($extension in $applicable) {
                    $definition = $definitions | Where-Object { $_.Key -eq $extension.Key } | Select-Object -First 1
                    if ($definition.AppliesTo -eq 'core' -and $objectIndex -gt 9) { continue }

                    $body[$extension.PropertyName] = switch ($definition.DataType) {
                        'Boolean' { ($objectIndex % 3) -eq 0 }
                        # Deliberately zero on some objects: zero is falsy, and a script using
                        # if ($value) drops it without noticing.
                        'Integer' { ($objectIndex % 4) * 25 }
                        'LargeInteger' { [int64]$definition.SampleValue }
                        'DateTime' { $definition.SampleValue }
                        'Binary' { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($marker.Tag):$objectIndex")) }
                        default {
                            ($definition.SampleValue -replace '\{Tag\}', $marker.Tag) -replace '\{Index\}', $objectIndex
                        }
                    }
                }

                if ($body.Count -eq 0) { continue }

                $requests.Add([PSCustomObject]@{
                        Reference = $object.id
                        Method    = 'PATCH'
                        Url       = "/$($type.ToLower())/$($object.id)"
                        Body      = $body
                    })
            }
        }

        if ($requests.Count -gt 0) {
            Write-Verbose "Writing extension values to $($requests.Count) object(s)"

            # A just-created extension is not immediately usable. Verified live: the PATCH is
            # rejected with "The following extension properties are not available" for a few
            # seconds after the definition is created, which reads like the attribute does not
            # exist rather than like a replication delay.
            $results = @(Invoke-EntraBatch -Request $requests.ToArray() -Connection $connection -RetryOnNotFound `
                    -RetryOnErrorMatch 'extension properties are not available' `
                    -Activity 'Writing extension values' -ShowProgress:$ShowProgress)

            $failed = @($results | Where-Object { -not $_.Success })
            if ($failed.Count -gt 0) {
                Write-Warning "$($failed.Count) object(s) did not receive their extension values. First error: $($failed[0].Error)"
            }
        }
    }

    Write-TestProgress -Activity 'Seeding directory extensions' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
