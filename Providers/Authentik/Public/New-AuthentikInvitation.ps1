function New-AuthentikInvitation {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded enrolment invitations from Data\AuthentikInvitations.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$InvitationName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikInvitations.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($InvitationName) {
        $rows = @($rows | Where-Object { $InvitationName -contains $_.Name })
        $unknown = @($InvitationName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalInvitations   = $rows.Count
        CreatedInvitations = 0
        UpdatedInvitations = 0
        Invitations        = @()
        Errors             = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Invitations -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    # An invitation tied to a flow can be redeemed only through that flow. The seeded flows
    # are resolved by the slug the flows file gives them, so the CSV never sees a UUID.
    $flowPkByKey = @{}
    if (@($rows | Where-Object { $_.Flow }).Count -gt 0) {
        $flowRows = @(Import-Csv -Path (Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikFlows.csv') -Encoding UTF8)
        $seededFlows = @(Get-AuthentikSeededObject -Type Flows -Connection $connection)
        foreach ($flowRow in $flowRows) {
            $slug = '{0}-{1}' -f $marker.SlugPrefix, $flowRow.Slug
            $match = @($seededFlows | Where-Object { $_.slug -eq $slug })
            if ($match.Count -gt 0) { $flowPkByKey[$flowRow.Name] = [string]$match[0].pk }
        }
    }

    $invitations = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $marker.SlugPrefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik invitation')) { continue }

        try {
            $fixedData = ConvertFrom-AuthentikSetting -Text $row.FixedData
            $fixedData[$marker.Attribute] = $marker.Tag

            $expires = [DateTimeOffset]::UtcNow.AddDays([int]$row.ExpiresInDays)
            $body = @{
                name       = $name
                expires    = $expires.ToString('o')
                single_use = ($row.SingleUse -eq 'TRUE')
                fixed_data = $fixedData
            }
            $flowSlug = $null
            if ($row.Flow) {
                if ($flowPkByKey.ContainsKey($row.Flow)) {
                    $body.flow = $flowPkByKey[$row.Flow]
                    $flowSlug = $row.Flow
                }
                else {
                    $message = "Invitation '$name' is tied to flow '$($row.Flow)', which does not exist. Created for any flow."
                    $result.Errors += $message
                    Write-Warning $message
                }
            }

            $invitation = $null
            if ($existingByName.ContainsKey($name)) {
                $invitation = Invoke-AuthentikRequest -Method PATCH -Path "/stages/invitation/invitations/$($existingByName[$name].pk)/" -Body $body -Connection $connection
                $result.UpdatedInvitations++
                Write-Verbose "Updated invitation $name"
            }
            else {
                $invitation = Invoke-AuthentikRequest -Method POST -Path '/stages/invitation/invitations/' -Body $body -Connection $connection
                $result.CreatedInvitations++
                Write-Verbose "Created invitation $name"
            }

            $invitations.Add([PSCustomObject]@{
                    Id        = [string]$invitation.pk
                    Key       = $row.Name
                    Name      = $name
                    Expires   = $expires.UtcDateTime
                    SingleUse = ($row.SingleUse -eq 'TRUE')
                    Flow      = $flowSlug
                })
        }
        catch {
            $message = "Failed to create invitation '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Invitations = $invitations.ToArray()

    Write-Verbose ("Invitations: $($result.CreatedInvitations) created, $($result.UpdatedInvitations) updated, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
