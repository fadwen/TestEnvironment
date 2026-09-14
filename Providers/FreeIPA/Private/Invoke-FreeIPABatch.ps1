function Invoke-FreeIPABatch {
    <#
    .SYNOPSIS
        Sends many FreeIPA commands in a few round trips through the JSON-RPC batch method
    .DESCRIPTION
        FreeIPA answers one command in well under a second, but the seed had 357 users, 413
        hosts and 836 DNS records to create one call each, and the round trip was where the
        thirteen minutes went. The realm's batch method carries a list of commands in one
        request and answers with one result per command, in order, so a step can decide every
        object one at a time and send them fifty at a time.

        Each command is a Method, its Arguments, its Options and, optionally, the IgnoreError
        names Invoke-FreeIPARequest would have taken and a Tag for the caller to find its answer
        by. Each answer carries the command back with Success, Ignored, Result (the command's
        envelope, so .result is the entry as with Invoke-FreeIPARequest), ErrorName and
        ErrorMessage. A command the realm refused fails alone; the others in its chunk stand. A
        chunk the realm could not take at all - a transport failure, an expired session that
        could not be renewed - fails every command in it with the same message, so no command
        is ever silently unanswered.
    .PARAMETER Command
        The commands, as hashtables or objects with Method, Arguments, Options, IgnoreError, Tag
    .PARAMETER ChunkSize
        How many commands travel in one request
    .PARAMETER Connection
        The connection; the active one when omitted
    .OUTPUTS
        PSCustomObject typed FreeIPABatchResult, one per command, in order
    .EXAMPLE
        PS> Invoke-FreeIPABatch -Command @(@{ Method = 'user_add'; Arguments = @('jnino'); Options = $options; Tag = 'jnino' })

        One user, one answer, with Success and the entry.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Command,

        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$ChunkSize = 50,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }
    $commands = @($Command | Where-Object { $null -ne $_ })
    if ($commands.Count -eq 0) { return }

    $answerFor = {
        param($item, $success, $ignored, $result, $name, $message)
        [PSCustomObject]@{
            PSTypeName   = 'FreeIPABatchResult'
            Command      = $item
            Success      = [bool]$success
            Ignored      = [bool]$ignored
            Result       = $result
            ErrorName    = $name
            ErrorMessage = $message
        }
    }

    for ($start = 0; $start -lt $commands.Count; $start += $ChunkSize) {
        $chunk = @($commands[$start..([Math]::Min($start + $ChunkSize - 1, $commands.Count - 1))])
        $calls = @(foreach ($item in $chunk) {
                $options = @{}
                if ($item.Options) {
                    foreach ($key in $item.Options.Keys) {
                        if ($null -ne $item.Options[$key]) { $options[[string]$key] = $item.Options[$key] }
                    }
                }
                if ($Connection.ApiVersion -and -not $options.ContainsKey('version')) { $options['version'] = [string]$Connection.ApiVersion }
                @{ method = [string]$item.Method; params = @(, [object[]]@($item.Arguments)) + @(, $options) }
            })

        $answers = @()
        try {
            $envelope = Invoke-FreeIPARequest -Method 'batch' -Arguments $calls -Options @{} -Connection $Connection
            if ($envelope -and $envelope.PSObject.Properties['results']) { $answers = @($envelope.results) }
        }
        catch {
            $message = $_.Exception.Message
            foreach ($item in $chunk) { & $answerFor $item $false $false $null 'BatchFailed' $message }
            continue
        }

        for ($i = 0; $i -lt $chunk.Count; $i++) {
            $item = $chunk[$i]
            $answer = if ($i -lt $answers.Count) { $answers[$i] } else { $null }
            if ($null -eq $answer) {
                & $answerFor $item $false $false $null 'NoAnswer' "FreeIPA $($item.Method) went unanswered in its batch."
                continue
            }
            $errorText = if ($answer.PSObject.Properties['error']) { [string]$answer.error } else { '' }
            if (-not $errorText) {
                & $answerFor $item $true $false $answer $null $null
                continue
            }
            $errorName = if ($answer.PSObject.Properties['error_name']) { [string]$answer.error_name } else { '' }
            if ($errorName -and @($item.IgnoreError) -contains $errorName) {
                Write-Verbose "FreeIPA $($item.Method) answered $errorName, which the caller expected."
                & $answerFor $item $true $true $null $errorName $errorText
                continue
            }
            $errorCode = if ($answer.PSObject.Properties['error_code']) { [string]$answer.error_code } else { '' }
            & $answerFor $item $false $false $null $errorName ("FreeIPA $($item.Method) failed ($errorName $errorCode): $errorText" -replace '\s+\)', ')')
        }
    }
}
