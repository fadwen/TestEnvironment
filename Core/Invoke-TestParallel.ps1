function Invoke-TestParallel {
    <#
    .SYNOPSIS
        Runs one script block over many items on a pool of runspaces that have this module loaded
    .DESCRIPTION
        For a provider whose API answers one request in about a second and offers no batch
        endpoint, the seed's time is spent waiting on the wire one object at a time, and the only
        lever is to wait on several at once. This runs the block for every item on a runspace pool
        of -ThrottleLimit workers, in module scope, so the block can call the module's own request
        function. Windows PowerShell 5.1 has no ForEach-Object -Parallel, and a runspace pool is
        what that cmdlet is built on.

        Each worker runspace imports this module afresh, so it has the module's functions and its
        constants but none of the session's state: no active connection, no cached anything. The
        same rule as Start-Job applies, and a contract test enforces it: the block reads no
        $script: variable, and everything it needs travels in through -Parameter or the item.
        The block receives $Item and $Parameter, in that order.

        Results come back one per item, in the order the items were given, whatever order the
        workers finished in. A block that throws for one item fails that item alone: its message
        is in Error, Success is $false, and every other item is unaffected. A warning the block
        writes reaches the host as it happens, through the pool's host.

        Pester mocks live in the test runspace and do not reach a worker, so a suite that covers a
        caller of this function mocks the function itself with a body that runs the block inline.
    .PARAMETER InputObject
        The items, one block invocation each
    .PARAMETER ScriptBlock
        The work, taking $Item and $Parameter
    .PARAMETER Parameter
        What every invocation needs beyond its item: the connection, a password, a marker
    .PARAMETER ThrottleLimit
        How many workers run at once
    .PARAMETER Activity
        A progress bar's activity; nothing is drawn when it is not given
    .PARAMETER ShowProgress
        Draws the progress bar
    .OUTPUTS
        PSCustomObject typed TestParallelResult per item: Index, Input, Output, Error, Success
    .EXAMPLE
        PS> Invoke-TestParallel -InputObject $rows -Parameter @{ Connection = $connection } -ScriptBlock {
                param($Item, $Parameter)
                Invoke-AuthentikRequest -Method POST -Path '/core/users/' -Body $Item.Body -Connection $Parameter.Connection
            }

        Creates the users four at a time and returns one result per row, in row order.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [hashtable]$Parameter = @{},

        [Parameter()]
        [ValidateRange(1, 32)]
        [int]$ThrottleLimit = 4,

        [Parameter()]
        [string]$Activity,

        [Parameter()]
        [switch]$ShowProgress
    )

    $items = @($InputObject | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return }

    $manifest = Join-Path -Path $script:TestEnvironmentModuleRoot -ChildPath 'TestEnvironment.psd1'
    $initial = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $initial.ImportPSModule($manifest)
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $initial, $Host)
    $pool.Open()

    # The block travels as text and is rebuilt in the worker, then run inside the module there,
    # so it sees the module's functions rather than the worker's global scope.
    $body = $ScriptBlock.ToString()
    $runner = @'
param($ModuleName, $Body, $Item, $Parameter)
$module = Get-Module -Name $ModuleName
if (-not $module) { throw "The $ModuleName module did not load in the worker runspace." }
& $module ([scriptblock]::Create($Body)) $Item $Parameter
'@

    $jobs = New-Object System.Collections.Generic.List[object]
    try {
        for ($i = 0; $i -lt $items.Count; $i++) {
            $shell = [System.Management.Automation.PowerShell]::Create()
            $shell.RunspacePool = $pool
            $null = $shell.AddScript($runner).AddArgument('TestEnvironment').AddArgument($body).AddArgument($items[$i]).AddArgument($Parameter)
            $jobs.Add([PSCustomObject]@{ Index = $i; Shell = $shell; Handle = $shell.BeginInvoke() })
        }

        $done = 0
        foreach ($job in $jobs) {
            $output = @()
            $failure = $null
            try {
                $output = @($job.Shell.EndInvoke($job.Handle))
            }
            catch {
                $exception = $_.Exception
                # The worker's own exception is wrapped in the invocation's; the inner one is the
                # message the block threw.
                while ($exception.InnerException -and $exception -is [System.Management.Automation.RuntimeException] -and $exception.Message -match 'Exception calling') { $exception = $exception.InnerException }
                $failure = $exception.Message
            }
            if (-not $failure -and $job.Shell.Streams.Error.Count -gt 0) {
                $failure = @($job.Shell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
            }
            $job.Shell.Dispose()

            $done++
            if ($Activity) {
                Write-TestProgress -Activity $Activity -Status "$done of $($items.Count)" `
                    -PercentComplete ([int](100 * $done / $items.Count)) -ShowProgress:$ShowProgress
            }

            [PSCustomObject]@{
                PSTypeName = 'TestParallelResult'
                Index      = $job.Index
                Input      = $items[$job.Index]
                Output     = $output
                Error      = $failure
                Success    = ($null -eq $failure)
            }
        }
        if ($Activity) { Write-TestProgress -Activity $Activity -Completed -ShowProgress:$ShowProgress }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
    }
}
