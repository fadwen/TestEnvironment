function New-OneLoginSelfRegistration {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded self-registration profile, always disabled, moderated and open to the lab domain only
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Key,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginSelfRegistrations.csv') -Encoding UTF8)
    if ($Key) { $rows = @($rows | Where-Object { $Key -contains $_.Key }) }

    $listed = Invoke-OneLoginRequest -Method GET -Path 'self_registration_profiles' -Connection $connection
    $byName = @{}
    foreach ($summary in @($listed.self_registration_profiles | Where-Object { $null -ne $_ })) { $byName[[string]$summary.name] = $summary }
    $ours = @{}
    foreach ($registration in @(Get-OneLoginSeededObject -Type SelfRegistration -Connection $connection)) { $ours[[string]$registration.id] = $registration }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $restored = 0

    foreach ($row in $rows) {
        $name = Resolve-OneLoginSeedName -Key $row.Name -Kind DisplayName -Connection $connection

        # The safe shape, and nothing else, has no parameter: disabled, so there is no public page;
        # moderated, so even an enabled one admits nobody without an administrator; open only to the
        # lab domain, which RFC 2606 reserves, so no real address can register; and no default role
        # or group, so a registrant could never land in anything.
        $safe = [ordered]@{
            name                    = $name
            url                     = (Resolve-OneLoginSeedName -Key $row.Key -Kind Username -Connection $connection)
            enabled                 = $false
            moderated               = $true
            helptext                = $marker.Description
            email_verification_type = 'Email MagicLink'
            domain_list_strategy    = 0
            domain_whitelist        = [string]$connection.EmailDomain
            default_role_id         = $null
            default_group_id        = $null
        }

        if ($byName.ContainsKey($name)) {
            $summary = $byName[$name]
            $registration = $ours[[string]$summary.id]
            if (-not $registration) {
                $errors.Add("Self-registration profile '$name' already exists without the seed tag in its help text. It is somebody else's; it is left alone.")
                continue
            }
            $reused.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $registration.id })

            # Put the safe shape back if anybody loosened it.
            $loosened = $registration.enabled -or -not $registration.moderated -or $registration.default_role_id -or $registration.default_group_id -or
                ([string]$registration.domain_whitelist -ne [string]$connection.EmailDomain)
            if ($loosened -and $PSCmdlet.ShouldProcess($name, 'Restore the seeded self-registration profile to disabled and moderated')) {
                try {
                    $null = Invoke-OneLoginRequest -Method PUT -Path "self_registration_profiles/$($registration.id)" -Body @{ self_registration_profile = $safe } -Connection $connection
                    $restored++
                }
                catch { $errors.Add("Could not restore self-registration profile ${name}: $($_.Exception.Message)") }
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Create OneLogin self-registration profile')) { continue }
        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'self_registration_profiles' -Body @{ self_registration_profile = $safe } -Connection $connection
            $id = if ($result.self_registration_profile) { $result.self_registration_profile.id } else { $result.id }
            $created.Add([PSCustomObject]@{ Key = $row.Key; Name = $name; Id = $id })
            Write-Verbose "Created self-registration profile $name, disabled"
        }
        catch {
            $errors.Add("Could not create self-registration profile ${name}: $($_.Exception.Message)")
            Write-Warning "Could not create self-registration profile ${name}: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalSelfRegistrations   = @($rows).Count
            CreatedSelfRegistrations = $created.Count
            ReusedSelfRegistrations  = $reused.Count
            Restored                 = $restored
            SelfRegistrations        = (@($created) + @($reused))
            Errors                   = $errors.ToArray()
        }
    }
}
