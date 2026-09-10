function New-AuthentikToken {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded user tokens from Data\AuthentikTokens.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Identifier,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikTokens.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($Identifier) {
        $rows = @($rows | Where-Object { $Identifier -contains $_.Identifier })
        $unknown = @($Identifier | Where-Object { $rows.Identifier -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalTokens   = $rows.Count
        CreatedTokens = 0
        UpdatedTokens = 0
        Tokens        = @()
        Errors        = @()
    }

    $userByName = @{}
    foreach ($user in (Get-AuthentikSeededObject -Type Users -Connection $connection)) {
        $userByName[[string]$user.username] = $user
    }

    $existingByIdentifier = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Tokens -Connection $connection)) {
        $existingByIdentifier[[string]$existing.identifier] = $existing
    }

    $tokens = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $tokenIdentifier = '{0}-{1}' -f $marker.SlugPrefix, $row.Identifier

        if (-not $PSCmdlet.ShouldProcess("$tokenIdentifier for $($row.User)", 'Create Authentik token')) { continue }

        try {
            if (-not $userByName.ContainsKey($row.User)) {
                $message = "Token '$tokenIdentifier' belongs to user '$($row.User)', which does not exist. Skipped."
                $result.Errors += $message
                Write-Warning $message
                continue
            }

            $expires = $null
            $body = @{
                identifier  = $tokenIdentifier
                intent      = $row.Intent
                user        = [int]$userByName[$row.User].pk
                description = $row.Description
                expiring    = $false
            }
            # Minutes, not days: an instance caps an app password at its default token
            # duration, thirty minutes out of the box, and refuses anything longer. An API
            # token's expiry is set by the server whatever is sent, so only the app passwords
            # carry one here.
            if ($row.ExpiresInMinutes -match '^-?\d+$') {
                $expires = [DateTimeOffset]::UtcNow.AddMinutes([int]$row.ExpiresInMinutes)
                $body.expiring = $true
                $body.expires = $expires.ToString('o')
            }

            # The response is discarded on purpose: it never carries the secret, and nothing
            # here needs the object back.
            if ($existingByIdentifier.ContainsKey($tokenIdentifier)) {
                $null = Invoke-AuthentikRequest -Method PATCH -Path "/core/tokens/$tokenIdentifier/" -Body $body -Connection $connection
                $result.UpdatedTokens++
                Write-Verbose "Updated token $tokenIdentifier"
            }
            else {
                $null = Invoke-AuthentikRequest -Method POST -Path '/core/tokens/' -Body $body -Connection $connection
                $result.CreatedTokens++
                Write-Verbose "Created token $tokenIdentifier"
            }

            $tokens.Add([PSCustomObject]@{
                    Identifier = $tokenIdentifier
                    Key        = $row.Identifier
                    User       = $row.User
                    Intent     = $row.Intent
                    Expires    = $(if ($expires) { $expires.UtcDateTime } else { $null })
                    Expired    = ($null -ne $expires -and $expires -lt [DateTimeOffset]::UtcNow)
                })
        }
        catch {
            $message = "Failed to create token '$tokenIdentifier': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Tokens = $tokens.ToArray()

    Write-Verbose ("Tokens: $($result.CreatedTokens) created, $($result.UpdatedTokens) updated, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
