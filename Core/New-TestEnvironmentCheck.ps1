function New-TestEnvironmentCheck {
    <#
    .SYNOPSIS
        Builds one verification check from what the seed data expects and what the directory holds
    .DESCRIPTION
        Every provider's Test-<Provider>Environment reduces to a list of these. A check compares
        two sets of identifiers, or two counts, or a list of value mismatches, and records what was
        expected, what was found, what is missing, what is there that should not be, and whether
        it passed. Shaping the result in one place is what lets Test-TestEnvironment return the
        same object for every provider, and lets one renderer print all of them.

        Three kinds of check:

        - Identity. -Expected and -Found are identifiers - logins, names, distinguished names,
          "group <- member" pairs. Missing is what was expected and not found; Unexpected is what
          was found and not expected. -IgnoreCase compares them case-insensitively, for the
          identifiers a directory folds itself: a UPN, a SAM account name, an Okta login. Names are
          compared exactly, by codepoint, because a decomposed and a precomposed name are the same
          string to -eq and different strings on the wire. -MissingOnly leaves Unexpected empty and
          out of the verdict, for memberships, where a dynamic rule or an automember rule adds
          members the data never lists.

        - Value. -Compared says how many values were compared and -Mismatch lists the ones that
          differed, already described. Used for names, where the caller has to say which object
          carried which wrong value.

        - Count. -FoundCount, with or without -ExpectedCount. Without an expectation the check is
          observational: it records what is there and takes no part in the verdict, which is how
          object types whose expected number depends on the tenant's licence are reported.
    .PARAMETER Name
        What is being checked, as the console line and the result object name it
    .PARAMETER Expected
        The identifiers the seed data says should exist
    .PARAMETER Found
        The identifiers the directory holds
    .PARAMETER IgnoreCase
        Compare identifiers case-insensitively
    .PARAMETER MissingOnly
        Report only what is missing; identifiers found beyond the expected set are not a failure
    .PARAMETER Compared
        How many values were compared for a value check
    .PARAMETER Mismatch
        The values that differed, one description each
    .PARAMETER FoundCount
        How many objects the directory holds, for a count check
    .PARAMETER ExpectedCount
        How many objects the seed data says there should be; omit to record the count without judging it
    .OUTPUTS
        PSCustomObject typed TestEnvironmentCheck, with Name, Kind, Expected, Found, Missing,
        Unexpected and Passed. Passed is $null for an observational count.
    .EXAMPLE
        PS> New-TestEnvironmentCheck -Name 'Users' -Expected $upns -Found $directory.userPrincipalName -IgnoreCase

        Compares the seeded UPNs with the directory's and names the ones missing on either side.
    .EXAMPLE
        PS> New-TestEnvironmentCheck -Name 'Conditional Access policies' -FoundCount $policies.Count

        Records how many policies are there without judging it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a result object in memory and changes nothing outside it.')]
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Identity')]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Expected,

        [Parameter(ParameterSetName = 'Identity')]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Found,

        [Parameter(ParameterSetName = 'Identity')]
        [switch]$IgnoreCase,

        [Parameter(ParameterSetName = 'Identity')]
        [switch]$MissingOnly,

        [Parameter(Mandatory = $true, ParameterSetName = 'Value')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Compared,

        [Parameter(ParameterSetName = 'Value')]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Mismatch,

        [Parameter(Mandatory = $true, ParameterSetName = 'Count')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$FoundCount,

        [Parameter(ParameterSetName = 'Count')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ExpectedCount
    )

    $result = [ordered]@{
        PSTypeName = 'TestEnvironmentCheck'
        Name       = $Name
        Kind       = $PSCmdlet.ParameterSetName
        Expected   = 0
        Found      = 0
        Missing    = @()
        Unexpected = @()
        Passed     = $null
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Identity' {
            $comparer = if ($IgnoreCase) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
            $expectedSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList $comparer
            $foundSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList $comparer
            foreach ($item in @($Expected)) { if ($null -ne $item -and $item -ne '') { $null = $expectedSet.Add($item) } }
            foreach ($item in @($Found)) { if ($null -ne $item -and $item -ne '') { $null = $foundSet.Add($item) } }

            # Sorted by ordinal, so two runs list the same names in the same order and a diff of two
            # results is about the directory rather than enumeration order or the host's culture.
            $missing = [string[]]@($expectedSet | Where-Object { -not $foundSet.Contains($_) })
            [Array]::Sort($missing, [System.StringComparer]::Ordinal)
            $unexpected = [string[]]@()
            if (-not $MissingOnly) {
                $unexpected = [string[]]@($foundSet | Where-Object { -not $expectedSet.Contains($_) })
                [Array]::Sort($unexpected, [System.StringComparer]::Ordinal)
            }

            $result.Expected = $expectedSet.Count
            $result.Found = $foundSet.Count
            $result.Missing = $missing
            $result.Unexpected = $unexpected
            $result.Passed = ($missing.Count -eq 0 -and $unexpected.Count -eq 0)
        }
        'Value' {
            $mismatches = @($Mismatch | Where-Object { $null -ne $_ -and $_ -ne '' })
            $result.Expected = $Compared
            $result.Found = [Math]::Max(0, $Compared - $mismatches.Count)
            $result.Missing = $mismatches
            $result.Passed = ($mismatches.Count -eq 0)
        }
        'Count' {
            $result.Found = $FoundCount
            if ($PSBoundParameters.ContainsKey('ExpectedCount')) {
                $result.Expected = $ExpectedCount
                $result.Passed = ($FoundCount -eq $ExpectedCount)
            }
            else {
                $result.Expected = $null
            }
        }
    }

    return [PSCustomObject]$result
}
