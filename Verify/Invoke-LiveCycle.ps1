<#
.SYNOPSIS
    Seeds, verifies, tears down and re-verifies one live provider through the exported commands
.DESCRIPTION
    The full cycle against a real tenant, domain, org, instance, realm or environment, using only
    what the module exports: Connect-TestEnvironment with the parameters given, New-TestEnvironment,
    Test-TestEnvironment (which must pass), Remove-TestEnvironment -Force, and Test-TestEnvironment
    again, which must now find nothing the module owns. Any other outcome is a non-zero exit.

    This is a development tool, not part of the module: nothing under Verify/ ships. It exists so
    the claim "verified live" in the changelog is one command anybody with a lab can repeat, and
    so the unit suite, which reaches no directory, is not the only evidence that a provider works.

    The module is imported from the repository root beside this folder, so what runs is the
    working tree, not an installed copy.
.PARAMETER Provider
    The provider to cycle, as Connect-TestEnvironment names it
.PARAMETER ConnectParameter
    Everything Connect-TestEnvironment needs beyond -Provider, as a hashtable to splat
.PARAMETER SeedParameter
    Anything to pass to New-TestEnvironment, such as a step to skip
.PARAMETER SkipSeed
    Verify and tear down what is already there rather than seeding first
.PARAMETER SkipTeardown
    Seed and verify, then leave the estate in place
.PARAMETER PassThru
    Return the two verification results as well as writing the summary
.EXAMPLE
    PS> ./Verify/Invoke-LiveCycle.ps1 -Provider PingOne -ConnectParameter @{ EnvironmentId = $env; ClientId = $client; UseStoredSecret = $true }

    Seeds the PingOne sandbox, verifies it, removes it, and verifies the removal.
.EXAMPLE
    PS> ./Verify/Invoke-LiveCycle.ps1 -Provider AD -ConnectParameter @{} -SkipSeed

    Verifies and removes whatever is seeded in the connected domain.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Entra', 'AD', 'Okta', 'Authentik', 'FreeIPA', 'PingOne')]
    [string]$Provider,

    [Parameter()]
    [hashtable]$ConnectParameter = @{},

    [Parameter()]
    [hashtable]$SeedParameter = @{},

    [Parameter()]
    [switch]$SkipSeed,

    [Parameter()]
    [switch]$SkipTeardown,

    [Parameter()]
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'TestEnvironment.psd1') -Force

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$step = { param($text) Write-Information ('[{0:mm\:ss}] {1}' -f $stopwatch.Elapsed, $text) -InformationAction Continue }

& $step "Connecting to $Provider"
Connect-TestEnvironment -Provider $Provider @ConnectParameter | Out-Null

if (-not $SkipSeed) {
    & $step 'Seeding'
    New-TestEnvironment @SeedParameter | Out-Null
}

& $step 'Verifying the seed'
$seeded = Test-TestEnvironment
$failures = New-Object System.Collections.Generic.List[string]
if (-not $seeded.Passed) {
    foreach ($check in @($seeded.Checks | Where-Object { $_.Passed -eq $false })) {
        $failures.Add(('after seeding, {0}: {1} missing, {2} unexpected' -f $check.Name, @($check.Missing).Count, @($check.Unexpected).Count))
    }
}

$removed = $null
if (-not $SkipTeardown) {
    if ($PSCmdlet.ShouldProcess($Provider, 'Remove the seeded environment')) {
        & $step 'Tearing down'
        Remove-TestEnvironment -Force | Out-Null

        & $step 'Verifying the teardown'
        $removed = Test-TestEnvironment -SkipMembership -Quiet
        # After teardown every identity check must find nothing. The observational counts must be
        # zero too: a leftover named location or role eligibility is a leftover.
        foreach ($check in @($removed.Checks | Where-Object { $_.Kind -ne 'Value' -and $_.Found -gt 0 })) {
            $failures.Add(('after teardown, {0}: {1} still found' -f $check.Name, $check.Found))
        }
    }
}

& $step 'Done'
if ($failures.Count -eq 0) {
    Write-Information "$Provider cycle verified." -InformationAction Continue
}
else {
    foreach ($failure in $failures) { Write-Warning $failure }
    Write-Warning "$Provider cycle NOT verified: $($failures.Count) finding(s)."
}

if ($PassThru) {
    [PSCustomObject]@{ Provider = $Provider; Seeded = $seeded; Removed = $removed; Failures = $failures.ToArray() }
}

if ($failures.Count -gt 0) { exit 1 }
