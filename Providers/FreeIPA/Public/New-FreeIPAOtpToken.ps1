function New-FreeIPAOtpToken {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded OTP tokens from Data\FreeIPAOtpTokens.csv on their users
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$TokenId,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPAOtpTokens.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($TokenId) {
        $rows = @($rows | Where-Object { $TokenId -contains $_.Id })
        $unknown = @($TokenId | Where-Object { $rows.Id -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalTokens   = $rows.Count
        CreatedTokens = 0
        UpdatedTokens = 0
        Tokens        = @()
        Errors        = @()
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type OtpTokens -Connection $connection)) { $existing[[string](@($entry.ipatokenuniqueid)[0])] = $entry }

    $tokens = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $id = Resolve-FreeIPASeedName -Key $row.Id -Marker $marker -Connection $connection
        if (-not $PSCmdlet.ShouldProcess("$id for $($row.Owner)", 'Create FreeIPA OTP token')) { continue }
        try {
            $mutable = @{
                description      = ('{0} {1}' -f $row.Description, $marker.Marker).Trim()
                ipatokendisabled = ($row.Enabled -eq 'FALSE')
            }
            if ($row.ExpiresInDays -match '^-?\d+$') {
                $mutable['ipatokennotafter'] = ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::UtcNow.AddDays([int]$row.ExpiresInDays))
            }
            if ($row.Vendor) { $mutable['ipatokenvendor'] = $row.Vendor }
            if ($row.Model) { $mutable['ipatokenmodel'] = $row.Model }

            if ($existing.ContainsKey($id)) {
                $null = Invoke-FreeIPARequest -Method 'otptoken_mod' -Arguments $id -Options $mutable -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedTokens++
            }
            else {
                $options = @{
                    type                 = $row.Type
                    ipatokenowner        = $row.Owner
                    ipatokenotpalgorithm = $row.Algorithm
                    ipatokenotpdigits    = [int]$row.Digits
                    no_qrcode            = $true
                }
                foreach ($key in $mutable.Keys) { $options[$key] = $mutable[$key] }
                # The answer carries the secret and its URI. Discarded on the spot.
                $null = Invoke-FreeIPARequest -Method 'otptoken_add' -Arguments $id -Options $options -Connection $connection
                $result.CreatedTokens++
                Write-Verbose "Created OTP token $id"
            }

            $tokens.Add([PSCustomObject]@{
                    Key     = $row.Id
                    Id      = $id
                    Owner   = $row.Owner
                    Type    = $row.Type
                    Enabled = ($row.Enabled -ne 'FALSE')
                    Expired = ($row.ExpiresInDays -match '^-\d+$')
                })
        }
        catch {
            $message = "Failed to create OTP token '$id': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Tokens = $tokens.ToArray()
    Write-Verbose "OTP tokens: $($result.CreatedTokens) created, $($result.UpdatedTokens) updated, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
