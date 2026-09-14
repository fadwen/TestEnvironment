function New-TestEnvironmentVerification {
    <#
    .SYNOPSIS
        Assembles a provider's checks into one verification result and prints it
    .DESCRIPTION
        The object every Test-<Provider>Environment returns, so a script can read .Passed from
        whichever provider is connected and a person can read the same console lines. A check
        that passed prints as a success, one that failed prints as a warning with the first few
        missing and unexpected names, and an observational count prints as information. The
        verdict is the conjunction of every check that has one: a check whose Passed is $null
        takes no part in it.
    .PARAMETER Provider
        The provider the checks came from, as Get-TestEnvironmentProvider names it
    .PARAMETER Target
        The tenant, domain, org, instance, realm or environment that was checked, for the header
    .PARAMETER Check
        The checks, as New-TestEnvironmentCheck built them
    .PARAMETER Quiet
        Return the result without writing anything to the console
    .OUTPUTS
        PSCustomObject typed TestEnvironmentVerification, with Provider, Target, VerifiedOn,
        Checks, Failed and Passed.
    .EXAMPLE
        PS> New-TestEnvironmentVerification -Provider Okta -Target 'https://dev-1.okta.com' -Check $checks

        Prints one line per check and a verdict, and returns the result.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a result object in memory and changes nothing outside it.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Provider,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Target,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Check,

        [Parameter()]
        [switch]$Quiet
    )

    $checks = @($Check | Where-Object { $null -ne $_ })
    $judged = @($checks | Where-Object { $null -ne $_.Passed })
    $failed = @($judged | Where-Object { -not $_.Passed })

    if (-not $Quiet) {
        $where = if ($Target) { " against $Target" } else { '' }
        Write-TestMessage -Message "Verifying the $Provider seed$where" -Type Header

        foreach ($item in $checks) {
            if ($null -eq $item.Passed) {
                Write-TestMessage -Message ('{0}: {1} found' -f $item.Name, $item.Found) -Type Info
                continue
            }
            if ($item.Passed) {
                $line = switch ($item.Kind) {
                    'Value' { '{0}: {1} compared, all match' -f $item.Name, $item.Expected }
                    'Count' { '{0}: {1} of {2}' -f $item.Name, $item.Found, $item.Expected }
                    # Expected of expected, not found of expected: a membership check that judges
                    # only what is missing can find more than the data lists and still pass.
                    default { '{0}: {1} of {2} present' -f $item.Name, $item.Expected, $item.Expected }
                }
                Write-TestMessage -Message $line -Type Success
                continue
            }

            $parts = New-Object System.Collections.Generic.List[string]
            switch ($item.Kind) {
                'Value' { $parts.Add(('{0} of {1} differ' -f @($item.Missing).Count, $item.Expected)) }
                'Count' { $parts.Add(('{0} found, {1} expected' -f $item.Found, $item.Expected)) }
                default {
                    $present = $item.Expected - @($item.Missing).Count
                    $parts.Add(('{0} of {1} present' -f $present, $item.Expected))
                }
            }
            if (@($item.Missing).Count -gt 0) {
                $label = if ($item.Kind -eq 'Value') { 'differing' } else { 'missing' }
                $parts.Add(('{0}: {1}' -f $label, (Format-TestEnvironmentSample -Item $item.Missing)))
            }
            if (@($item.Unexpected).Count -gt 0) {
                $parts.Add(('unexpected: {0}' -f (Format-TestEnvironmentSample -Item $item.Unexpected)))
            }
            Write-TestMessage -Message ('{0}: {1}' -f $item.Name, ($parts -join '; ')) -Type Warning
        }

        if ($judged.Count -eq 0) {
            Write-TestMessage -Message 'Nothing was judged: every check was observational.' -Type Warning
        }
        elseif ($failed.Count -eq 0) {
            Write-TestMessage -Message ('Verified: all {0} checks passed.' -f $judged.Count) -Type Success
        }
        else {
            Write-TestMessage -Message ('Not verified: {0} of {1} checks failed.' -f $failed.Count, $judged.Count) -Type Error
        }
    }

    return [PSCustomObject]@{
        PSTypeName = 'TestEnvironmentVerification'
        Provider   = $Provider
        Target     = $Target
        VerifiedOn = Get-Date
        Checks     = $checks
        Failed     = $failed.Count
        Passed     = ($judged.Count -gt 0 -and $failed.Count -eq 0)
    }
}
