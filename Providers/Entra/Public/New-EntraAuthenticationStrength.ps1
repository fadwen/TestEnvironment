function New-EntraAuthenticationStrength {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates custom authentication strength policies
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraAuthenticationStrength')]
    param(
        [Parameter()]
        [string[]]$StrengthKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraAuthenticationStrengths')
    if ($StrengthKey) {
        $definitions = @($definitions | Where-Object { $StrengthKey -contains $_.Key })
        $missing = @($StrengthKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for strength key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    $existing = @(Get-EntraSeededObject -Type AuthenticationStrengths -Connection $connection)
    $created = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName

        Write-TestProgress -Activity 'Seeding authentication strengths' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        $already = $existing | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1
        if ($already) {
            Write-Verbose "Authentication strength '$displayName' already exists"
            $created.Add([PSCustomObject]@{
                    PSTypeName          = 'EntraAuthenticationStrength'
                    Key                 = $definition.Key
                    Id                  = $already.id
                    DisplayName         = $displayName
                    AllowedCombinations = @($already.allowedCombinations)
                    Purpose             = $definition.Purpose
                })
            continue
        }

        # Semicolon, not comma. A single allowed combination is itself a comma-joined string
        # such as 'password,sms', so splitting on commas would send Entra a list of names it
        # rejects one at a time.
        $combinations = @($definition.AllowedCombinations -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        if ($combinations.Count -eq 0) {
            Write-Error "Authentication strength '$($definition.Key)' lists no allowed combinations." -ErrorAction Continue
            continue
        }

        # Checked before sending, because the limit is not documented on the request and the
        # failure names a length rather than the prefix that caused it. 30 characters is the
        # whole displayName, so a longer -Prefix eats into the seed data's own names: with the
        # default ENTRALAB- that leaves 21.
        if ($displayName.Length -gt 30) {
            Write-Error ("Authentication strength name '$displayName' is $($displayName.Length) characters and Entra " +
                "caps it at 30. Shorten the DisplayName in the seed data, or connect with a shorter -Prefix " +
                "(the prefix '$($marker.Prefix)' uses $($marker.Prefix.Length) of the 30).") -ErrorAction Continue
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create authentication strength')) { continue }

        try {
            $strength = Invoke-EntraRequest -Method POST -Connection $connection `
                -Path '/identity/conditionalAccess/authenticationStrength/policies' -Body @{
                displayName         = $displayName
                description         = $marker.Description
                allowedCombinations = $combinations
            }
        }
        catch {
            Write-Error "Failed to create authentication strength '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName          = 'EntraAuthenticationStrength'
                Key                 = $definition.Key
                Id                  = $strength.id
                DisplayName         = $displayName
                AllowedCombinations = $combinations
                Purpose             = $definition.Purpose
            })

        Write-Verbose "Created authentication strength '$displayName' ($($strength.id))"
    }

    Write-TestProgress -Activity 'Seeding authentication strengths' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
