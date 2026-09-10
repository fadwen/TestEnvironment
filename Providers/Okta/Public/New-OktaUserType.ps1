function New-OktaUserType {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the second Okta user type and extends its schema
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$TypeName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaDataPath) 'OktaUserTypes.csv') -Encoding UTF8)
    if ($TypeName) {
        $rows = @($rows | Where-Object { $TypeName -contains $_.Name })
        $unknown = @($TypeName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No user type definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalTypes    = $rows.Count
        CreatedTypes  = 0
        ExistingTypes = 0
        Types         = @()
        Errors        = @()
    }

    $existingTypes = @(Invoke-OktaRequest -Method GET -Path '/api/v1/meta/types/user')
    $types = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        # The API name must be a bare identifier, so the prefix is carried in the display name
        # and description instead. Teardown matches on the name having the prefix in it.
        $typeName = Get-OktaUserTypeName -Prefix $connection.Prefix -UserTypeKey $row.Name
        $displayName = '{0}-{1}' -f $connection.Prefix, $row.DisplayName

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create Okta user type')) { continue }

        try {
            $existing = @($existingTypes | Where-Object { $_.name -eq $typeName })

            if ($existing.Count -gt 0) {
                $type = $existing[0]
                $result.ExistingTypes++
                Write-Verbose "Reusing user type $typeName"
            }
            else {
                # Okta refuses to create a user type for a long while after one has been
                # deleted, answering with a bare "request body was not well-formed" that names
                # nothing. Measured against a live org across three teardown-then-reseed runs:
                # still refused four minutes after the deletion, still at eight, still at
                # fifteen, and accepted instantly at about thirty-five. It is not the NAME being
                # reserved - a brand-new name was refused in the same window while a raw POST of
                # the byte-identical body succeeded once the window had passed.
                #
                # So the wait is deliberately short. Sitting for fifteen minutes and then failing
                # anyway is worse than failing in two and saying what to do: it hides a
                # recoverable condition behind a hang, and the caller still ends up with a
                # half-seeded org. Two minutes covers the genuinely transient case; beyond that
                # the orchestrator reports the step as failed and the message below says exactly
                # which command to re-run once Okta has settled.
                $type = Invoke-OktaPendingCleanupRequest -Method POST -MaxWaitSeconds 120 `
                    -Path '/api/v1/meta/types/user' -Body @{
                        name        = $typeName
                        displayName = $displayName
                        description = $row.Description
                    }
                $result.CreatedTypes++
                Write-Verbose "Created user type $typeName"
            }

            # Each type has its own schema, reachable only through the link on the type object.
            # There is no predictable path to build by hand, which is why this is captured here
            # and passed to New-OktaProfileAttribute rather than reconstructed later.
            $schemaPath = $null
            if ($type._links -and $type._links.schema -and $type._links.schema.href) {
                $schemaPath = ([uri]$type._links.schema.href).AbsolutePath
            }

            $types.Add([PSCustomObject]@{
                Id          = $type.id
                Key         = $row.Name
                Name        = $typeName
                DisplayName = $displayName
                SchemaPath  = $schemaPath
            })
        }
        catch {
            $message = "Failed to create user type '$typeName': $($_.Exception.Message)"

            # The one failure here that is recoverable by waiting, and the one a caller will
            # otherwise misread as a broken request. Say what it is and what to run, rather than
            # leaving them with a 400 that names nothing and an org missing a user type, its ten
            # schema attributes and the two users that belong to it.
            if ($_.Exception.Message -match 'HTTP 400' -and $_.Exception.Message -match 'was not well-formed') {
                $message += [Environment]::NewLine +
                'Okta refuses to create any user type for a period after one has been deleted, and reports ' +
                'it as this malformed-body error. Nothing is wrong with the request. Measured at roughly ' +
                'half an hour on a trial org. The rest of the environment is unaffected - re-run ' +
                '"New-TestEnvironment -Skip ServiceApp" later and it will create the type, its schema ' +
                'attributes and the two users that need it, reusing everything already there.'
            }

            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Types = $types.ToArray()

    if ($PassThru) { return $result }
}
