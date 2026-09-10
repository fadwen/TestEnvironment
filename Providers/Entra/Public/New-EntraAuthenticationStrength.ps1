function New-EntraAuthenticationStrength {
    <#
    .SYNOPSIS
        Creates custom authentication strength policies

    .DESCRIPTION
        An authentication strength is a named set of acceptable credential combinations, and it
        is a control shape Okta has no equivalent of: a grant that says not merely "prove it is
        you" but "prove it this way".

        Three are created, spanning the range that matters for outcome evaluation - one
        hardware-backed only, one passwordless, and one deliberately wide.

        The permissive one is the interesting one, and it is here because of a real finding
        from CaOutcome. **A custom strength is editable.** Widening it weakens every policy
        that references it, with no policy document changing at all, so a baseline that watches
        only Conditional Access policies will not notice. Seeding one gives that scenario
        something to catch.

        The combination names themselves contain commas - `password,sms` is one combination,
        not two - which is why the seed data separates them with semicolons. Splitting on the
        wrong character produces names Entra rejects individually rather than a single clear
        failure.

        These are also what the seeded Conditional Access policy uses. Without them it falls
        back to the tenant's built-in phishing-resistant strength, which works but means the
        policy references an object this module did not create and cannot vary.

    .PARAMETER StrengthKey
        Creates only the named strengths, by their Key column. Defaults to all of them.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created strengths

    .OUTPUTS
        EntraAuthenticationStrength[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraAuthenticationStrength

        DESCRIPTION: Creates all three custom strengths
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment, before the policies that reference them

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
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
