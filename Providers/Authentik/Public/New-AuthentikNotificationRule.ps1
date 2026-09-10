function New-AuthentikNotificationRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded notification rules and the webhook transports they deliver to
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RuleName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikNotificationRules.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($RuleName) {
        $rows = @($rows | Where-Object { $RuleName -contains $_.Name })
        $unknown = @($RuleName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules        = $rows.Count
        CreatedRules      = 0
        UpdatedRules      = 0
        TransportsCreated = 0
        Rules             = @()
        Errors            = @()
    }

    $existingRuleByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)) {
        $existingRuleByName[[string]$existing.name] = $existing
    }
    $existingTransportByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type NotificationTransports -Connection $connection)) {
        $existingTransportByName[[string]$existing.name] = $existing
    }

    $rules = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name
        $transportName = '{0}{1}' -f $marker.Prefix, $row.TransportName

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik notification rule')) { continue }

        try {
            $transportPk = $null
            if ($existingTransportByName.ContainsKey($transportName)) {
                $transportPk = [string]$existingTransportByName[$transportName].pk
            }
            else {
                $transport = Invoke-AuthentikRequest -Method POST -Path '/events/transports/' -Connection $connection -Body @{
                    name        = $transportName
                    mode        = 'webhook'
                    webhook_url = $row.WebhookUrl
                    send_once   = ($row.SendOnce -eq 'TRUE')
                }
                $transportPk = [string]$transport.pk
                $existingTransportByName[$transportName] = $transport
                $result.TransportsCreated++
                Write-Verbose "Created transport $transportName"
            }

            $body = @{
                name       = $name
                transports = @($transportPk)
                severity   = $row.Severity
            }

            $rule = $null
            if ($existingRuleByName.ContainsKey($name)) {
                $rule = Invoke-AuthentikRequest -Method PATCH -Path "/events/rules/$($existingRuleByName[$name].pk)/" -Body $body -Connection $connection
                $result.UpdatedRules++
                Write-Verbose "Updated rule $name"
            }
            else {
                $rule = Invoke-AuthentikRequest -Method POST -Path '/events/rules/' -Body $body -Connection $connection
                $result.CreatedRules++
                Write-Verbose "Created rule $name"
            }

            $rules.Add([PSCustomObject]@{
                    Id        = [string]$rule.pk
                    Key       = $row.Name
                    Name      = $name
                    Severity  = $row.Severity
                    Transport = $transportName
                    SendOnce  = ($row.SendOnce -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create notification rule '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Rules = $rules.ToArray()

    Write-Verbose ("Notification rules: $($result.CreatedRules) created, $($result.UpdatedRules) updated, " +
        "$($result.TransportsCreated) transports, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
