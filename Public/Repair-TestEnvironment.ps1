function Repair-TestEnvironment {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Puts back what verification found missing, by re-running only the seed steps that own it
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipMembership
    )

    begin {
        if (-not $script:ActiveProvider) {
            Write-Error 'Not connected. Run Connect-TestEnvironment -Provider <name> first.' -ErrorAction Stop
            return
        }
    }

    process {
        $provider = $script:ActiveProvider
        $verify = 'Test-{0}Environment' -f $provider
        $seed = 'New-{0}Environment' -f $provider
        foreach ($target in $verify, $seed) {
            if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
                Write-Error "The $provider provider does not implement $target." -ErrorAction Stop
                return
            }
        }
        $map = Get-Variable -Name ('{0}RepairStep' -f $provider) -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if (-not $map) {
            Write-Error "The $provider provider does not say which seed step owns which check, so it cannot be repaired." -ErrorAction Stop
            return
        }

        Write-TestMessage -Message "Repairing the $provider seed" -Type Header
        $before = & $verify -Quiet -SkipMembership:$SkipMembership
        $failed = @($before.Checks | Where-Object { $_.Passed -eq $false })
        $result = [ordered]@{
            PSTypeName = 'TestEnvironmentRepair'
            Provider   = $provider
            Before     = $before
            StepsRun   = @()
            SeedResult = $null
            After      = $null
            Repaired   = $null
        }

        if ($failed.Count -eq 0) {
            Write-TestMessage -Message 'Nothing to repair: every check passed.' -Type Success
            $result.Repaired = $true
            return [PSCustomObject]$result
        }

        # The steps that own what failed, plus what every repair needs around them.
        $steps = New-Object System.Collections.Generic.List[string]
        $unowned = New-Object System.Collections.Generic.List[string]
        foreach ($check in $failed) {
            $name = [string]$check.Name
            if ($map.Step.ContainsKey($name)) { if (-not $steps.Contains($map.Step[$name])) { $steps.Add($map.Step[$name]) } }
            else { $unowned.Add($name) }
            if (@($check.Unexpected).Count -gt 0) {
                Write-TestMessage -Message ("{0}: {1} object(s) the data does not describe are left alone; teardown removes them ({2})" -f $name, @($check.Unexpected).Count, (Format-TestEnvironmentSample -Item $check.Unexpected -Limit 3)) -Type Warning
            }
        }
        foreach ($name in $unowned) { Write-Warning "No seed step owns the check '$name', so it cannot be repaired here." }
        if ($steps.Count -eq 0) {
            Write-TestMessage -Message 'Nothing a seed step can put back.' -Type Warning
            $result.Repaired = $false
            return [PSCustomObject]$result
        }
        foreach ($always in @($map.Always)) { if (-not $steps.Contains($always)) { $steps.Add($always) } }

        # The orchestrator takes what to leave out; the rest of its steps are the ones to run.
        $skipParameter = (Get-Command -Name $seed).Parameters['Skip']
        $allSteps = @(@($skipParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0].ValidValues)
        $ordered = @($allSteps | Where-Object { $steps.Contains($_) })
        $skip = @($allSteps | Where-Object { -not $steps.Contains($_) })
        $result.StepsRun = $ordered

        Write-TestMessage -Message ("Failed: {0}. Re-running {1}." -f (@($failed | ForEach-Object { $_.Name }) -join ', '), ($ordered -join ', ')) -Type Info
        if (-not $PSCmdlet.ShouldProcess($provider, "Re-run the $($ordered -join ', ') step(s) of $seed")) {
            return [PSCustomObject]$result
        }

        $seedArguments = @{ PassThru = $true }
        if ($skip.Count -gt 0) { $seedArguments['Skip'] = $skip }
        $result.SeedResult = & $seed @seedArguments
        $after = & $verify -Quiet -SkipMembership:$SkipMembership
        $result.After = $after
        $result.Repaired = [bool]$after.Passed

        $stillFailed = @($after.Checks | Where-Object { $_.Passed -eq $false })
        if ($after.Passed) { Write-TestMessage -Message 'Repaired: every check passes.' -Type Success }
        else {
            Write-TestMessage -Message ("Not repaired: {0} check(s) still fail ({1})." -f $stillFailed.Count, (@($stillFailed | ForEach-Object { $_.Name }) -join ', ')) -Type Warning
        }
        return [PSCustomObject]$result
    }
}
