function Compare-TestEnvironment {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Compares the people two connected providers hold, the way a hybrid identity match would
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateCount(2, 2)]
        [string[]]$Provider,

        [Parameter()]
        [switch]$Quiet
    )

    $names = @($Provider | ForEach-Object { [string]$_ })
    foreach ($name in $names) {
        if (-not $script:TestEnvironmentProvider.ContainsKey($name)) {
            Write-Error ("No provider called '$name' is loaded. Available: " +
                (($script:TestEnvironmentProvider.Keys | Sort-Object) -join ', ')) -ErrorAction Stop
            return
        }
    }
    if ($names[0] -eq $names[1]) {
        Write-Error 'Name two different providers to compare.' -ErrorAction Stop
        return
    }

    $snapshots = foreach ($name in $names) {
        $reader = 'Get-{0}IdentitySnapshot' -f $name
        if (-not (Get-Command -Name $reader -ErrorAction SilentlyContinue)) {
            Write-Error "The $name provider does not implement $reader." -ErrorAction Stop
            return
        }
        try { & $reader }
        catch {
            throw (New-Object System.Exception(
                    "Could not read the seeded people from $name. Both providers must be connected in this session: $($_.Exception.Message)", $_.Exception))
        }
    }

    $result = Compare-TestIdentitySnapshot -Left $snapshots[0] -Right $snapshots[1]

    if (-not $Quiet) {
        Write-TestMessage -Message "Comparing the seeded people of $($result.Left.Provider) and $($result.Right.Provider)" -Type Header
        Write-TestMessage -Message ('{0}: {1} people in {2}' -f $result.Left.Provider, $result.Left.Count, $result.Left.Target) -Type Info
        Write-TestMessage -Message ('{0}: {1} people in {2}' -f $result.Right.Provider, $result.Right.Count, $result.Right.Target) -Type Info
        Write-TestMessage -Message ('Matched {0}: {1} by login key, {2} by display name' -f $result.Matched, $result.MatchedByKey, $result.MatchedByName) -Type Info
        foreach ($side in @(@{ Label = "Only in $($result.Left.Provider)"; Items = $result.OnlyLeft }, @{ Label = "Only in $($result.Right.Provider)"; Items = $result.OnlyRight })) {
            $count = @($side.Items).Count
            if ($count -eq 0) { Write-TestMessage -Message ('{0}: none' -f $side.Label) -Type Info }
            else { Write-TestMessage -Message ('{0}: {1} ({2})' -f $side.Label, $count, (Format-TestEnvironmentSample -Item $side.Items)) -Type Info }
        }
        if (@($result.StateDifference).Count -gt 0) {
            Write-TestMessage -Message ('Enabled differs for {0}, which the seed does on purpose ({1})' -f @($result.StateDifference).Count, (Format-TestEnvironmentSample -Item $result.StateDifference -Limit 3)) -Type Info
        }
        if ($result.Passed) {
            Write-TestMessage -Message ('Names agree by codepoint for all {0} matched people whose names both sides hold.' -f $result.NamesCompared) -Type Success
        }
        else {
            Write-TestMessage -Message ('Names differ for {0} of {1} matched people: {2}' -f @($result.NameMismatch).Count, $result.NamesCompared, (Format-TestEnvironmentSample -Item $result.NameMismatch -Limit 3)) -Type Error
        }
    }

    return $result
}
