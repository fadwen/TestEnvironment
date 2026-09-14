function Compare-TestIdentitySnapshot {
    <#
    .SYNOPSIS
        Compares the people two providers hold, by login key and then by name
    .DESCRIPTION
        The comparison behind Compare-TestEnvironment, kept apart from the reading so it can be
        tested on identities alone. Each side is a list of identities as Get-<Provider>IdentitySnapshot
        returns them: a Key, which is the login with whatever the provider added stripped off - the
        seed prefix, the UPN suffix, the email domain - so that jnino is jnino in every provider that
        keeps the shared logins; a DisplayName where the provider has one; GivenName and Surname where
        it has those; and Enabled.

        Matching is by Key first, then by DisplayName among what is left, because Active Directory's
        data logs its people in as first name and initial while every other provider uses the shared
        keys, and the two agree only on the names. What matches in neither way is reported as only on
        one side. That is not a fault: the providers deliberately hold different populations, and the
        report says so rather than judging it.

        For the pairs that matched, the names are compared by codepoint, never with -eq, which is
        what hybrid identity matching across two directories depends on: the display names where both
        sides have one, otherwise the given name and surname where both have those, otherwise nothing.
        A stored display name is never compared against one composed from parts.
        Enabled is compared and reported without a verdict, because the seed hangs different states on
        the same person in different providers on purpose. The verdict is the names alone.
    .PARAMETER Left
        The first provider's identities
    .PARAMETER Right
        The second provider's identities
    .OUTPUTS
        PSCustomObject typed TestEnvironmentComparison, with the two sides, MatchedByKey,
        MatchedByName, OnlyLeft, OnlyRight, NameMismatch, StateDifference and Passed
    .EXAMPLE
        PS> Compare-TestIdentitySnapshot -Left $entra -Right $pingOne

        Matches 329 people by key, reports the one PingOne-only account, and passes when every
        matched pair's names agree.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject]$Left,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject]$Right
    )

    $leftIdentities = @($Left.Identities | Where-Object { $null -ne $_ })
    $rightIdentities = @($Right.Identities | Where-Object { $null -ne $_ })

    $describe = { param($identity) if ($identity.DisplayName) { '{0} ({1})' -f $identity.Key, $identity.DisplayName } else { $identity.Key } }

    # By key first.
    $rightByKey = @{}
    foreach ($identity in $rightIdentities) {
        if ($identity.Key -and -not $rightByKey.ContainsKey($identity.Key)) { $rightByKey[[string]$identity.Key] = $identity }
    }
    $pairs = New-Object System.Collections.Generic.List[object]
    $matchedRight = New-Object 'System.Collections.Generic.HashSet[object]'
    $unmatchedLeft = New-Object System.Collections.Generic.List[object]
    foreach ($identity in $leftIdentities) {
        if ($identity.Key -and $rightByKey.ContainsKey($identity.Key)) {
            $other = $rightByKey[[string]$identity.Key]
            $pairs.Add([PSCustomObject]@{ Left = $identity; Right = $other; By = 'Key' })
            $null = $matchedRight.Add($other)
        }
        else { $unmatchedLeft.Add($identity) }
    }

    # Then by display name among what is left on both sides. Matched on the normalised,
    # case-folded form, so that a name one directory stored decomposed still finds its person
    # and the codepoint difference is then reported as the finding it is, rather than the two
    # spellings passing as two people who happen to be missing from each other's directory.
    $fold = { param($name) ([string]$name).Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant() }
    $rightByName = @{}
    foreach ($identity in $rightIdentities) {
        if ($matchedRight.Contains($identity)) { continue }
        if (-not $identity.DisplayName) { continue }
        $name = & $fold $identity.DisplayName
        if (-not $rightByName.ContainsKey($name)) { $rightByName[$name] = $identity }
    }
    $onlyLeft = New-Object System.Collections.Generic.List[string]
    foreach ($identity in $unmatchedLeft) {
        $name = if ($identity.DisplayName) { & $fold $identity.DisplayName } else { '' }
        if ($name -and $rightByName.ContainsKey($name) -and -not $matchedRight.Contains($rightByName[$name])) {
            $other = $rightByName[$name]
            $pairs.Add([PSCustomObject]@{ Left = $identity; Right = $other; By = 'Name' })
            $null = $matchedRight.Add($other)
        }
        else { $onlyLeft.Add((& $describe $identity)) }
    }
    $onlyRight = @($rightIdentities | Where-Object { -not $matchedRight.Contains($_) } | ForEach-Object { & $describe $_ })

    $nameMismatch = New-Object System.Collections.Generic.List[string]
    $stateDifference = New-Object System.Collections.Generic.List[string]
    $namesCompared = 0
    foreach ($pair in $pairs) {
        # Only the same kind of name against the same kind: display names where both sides keep
        # one, otherwise the given name and surname where both keep those. A stored display name
        # is never compared against one composed from parts, which would call every
        # family-name-first person a mismatch.
        $leftName = $null
        $rightName = $null
        if ($pair.Left.DisplayName -and $pair.Right.DisplayName) {
            $leftName = [string]$pair.Left.DisplayName
            $rightName = [string]$pair.Right.DisplayName
        }
        elseif (($pair.Left.GivenName -or $pair.Left.Surname) -and ($pair.Right.GivenName -or $pair.Right.Surname)) {
            $leftName = ('{0} {1}' -f $pair.Left.GivenName, $pair.Left.Surname).Trim()
            $rightName = ('{0} {1}' -f $pair.Right.GivenName, $pair.Right.Surname).Trim()
        }
        if ($null -ne $leftName) {
            $namesCompared++
            if (-not [string]::Equals($leftName, $rightName, [StringComparison]::Ordinal)) {
                $nameMismatch.Add(("{0}: {1} has '{2}', {3} has '{4}'" -f $pair.Left.Key, $Left.Provider, $leftName, $Right.Provider, $rightName))
            }
        }
        if ($null -ne $pair.Left.Enabled -and $null -ne $pair.Right.Enabled -and ([bool]$pair.Left.Enabled) -ne ([bool]$pair.Right.Enabled)) {
            $state = { param($enabled) if ($enabled) { 'enabled' } else { 'disabled' } }
            $stateDifference.Add(("{0}: {1} in {2}, {3} in {4}" -f $pair.Left.Key, (& $state $pair.Left.Enabled), $Left.Provider, (& $state $pair.Right.Enabled), $Right.Provider))
        }
    }

    $sort = { param($list) $array = [string[]]@($list); [Array]::Sort($array, [System.StringComparer]::Ordinal); $array }

    return [PSCustomObject]@{
        PSTypeName      = 'TestEnvironmentComparison'
        Left            = [PSCustomObject]@{ Provider = $Left.Provider; Target = $Left.Target; Count = $leftIdentities.Count }
        Right           = [PSCustomObject]@{ Provider = $Right.Provider; Target = $Right.Target; Count = $rightIdentities.Count }
        ComparedOn      = Get-Date
        Matched         = $pairs.Count
        MatchedByKey    = @($pairs | Where-Object { $_.By -eq 'Key' }).Count
        MatchedByName   = @($pairs | Where-Object { $_.By -eq 'Name' }).Count
        NamesCompared   = $namesCompared
        # Typed, so a list of one comes back as a list of one rather than as a string.
        OnlyLeft        = [string[]]@(& $sort $onlyLeft)
        OnlyRight       = [string[]]@(& $sort $onlyRight)
        NameMismatch    = [string[]]@(& $sort $nameMismatch)
        StateDifference = [string[]]@(& $sort $stateDifference)
        Passed          = ($nameMismatch.Count -eq 0)
    }
}
