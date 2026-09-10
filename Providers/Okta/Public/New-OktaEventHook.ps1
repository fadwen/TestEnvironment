function New-OktaEventHook {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded event hooks
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$HookName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaDataPath) 'OktaEventHooks.csv') -Encoding UTF8)
    if ($HookName) {
        $rows = @($rows | Where-Object { $HookName -contains $_.Name })
        $unknown = @($HookName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No event hook definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalHooks    = $rows.Count
        CreatedHooks  = 0
        ExistingHooks = 0
        Hooks         = @()
        Errors        = @()
    }

    $existingHooks = @(Invoke-OktaRequest -Method GET -Path '/api/v1/eventHooks' `
        -Query @{ limit = 200 } -Paginate)
    $hooks = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Okta event hook')) { continue }

        try {
            $existing = @($existingHooks | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $hook = $existing[0]
                $result.ExistingHooks++
                Write-Verbose "Reusing event hook $name"
            }
            else {
                $events = @($row.Events -split ';' | Where-Object { $_ })

                $hook = Invoke-OktaRequest -Method POST -Path '/api/v1/eventHooks' -Body @{
                    name    = $name
                    events  = @{ type = 'EVENT_TYPE'; items = $events }
                    channel = @{
                        type    = 'HTTP'
                        version = '1.0.0'
                        config  = @{ uri = $row.Uri }
                    }
                }
                $result.CreatedHooks++
                Write-Verbose "Created event hook $name"
            }

            $hooks.Add([PSCustomObject]@{
                Id     = $hook.id
                Key    = $row.Name
                Name   = $name
                Uri    = $row.Uri
                Status = $hook.status
                Events = @($row.Events -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create event hook '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Hooks = $hooks.ToArray()

    if ($PassThru) { return $result }
}
