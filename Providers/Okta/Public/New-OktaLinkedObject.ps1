function New-OktaLinkedObject {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the linked object definition and links seeded users with it
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipLinks,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaDataPath) 'OktaLinkedObjects.csv') -Encoding UTF8)

    $result = [PSCustomObject]@{
        Definitions  = @()
        LinksCreated = 0
        Errors       = @()
    }

    $userIdByLogin = @{}
    if (-not $SkipLinks) {
        $seeded = @(Get-OktaSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
        foreach ($user in $seeded) { $userIdByLogin[$user.profile.login] = $user.id }
    }

    $existing = @(Invoke-OktaRequest -Method GET -Path '/api/v1/meta/schemas/user/linkedObjects')
    $definitions = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        if (-not $PSCmdlet.ShouldProcess($row.PrimaryName, 'Create Okta linked object definition')) { continue }

        try {
            $alreadyThere = @($existing | Where-Object { $_.primary.name -eq $row.PrimaryName })

            if ($alreadyThere.Count -eq 0) {
                $null = Invoke-OktaRequest -Method POST `
                    -Path '/api/v1/meta/schemas/user/linkedObjects' -Body @{
                        primary = @{
                            name        = $row.PrimaryName
                            title       = $row.PrimaryTitle
                            description = $row.PrimaryDescription
                            type        = 'USER'
                        }
                        associated = @{
                            name        = $row.AssociatedName
                            title       = $row.AssociatedTitle
                            description = $row.AssociatedDescription
                            type        = 'USER'
                        }
                    }
                Write-Verbose "Created linked object definition $($row.PrimaryName)"
            }
            else {
                Write-Verbose "Reusing linked object definition $($row.PrimaryName)"
            }

            $linked = @()

            if (-not $SkipLinks) {
                foreach ($pair in @($row.Links -split ';' | Where-Object { $_ })) {
                    $parts = $pair -split '>'
                    if ($parts.Count -ne 2) {
                        $result.Errors += "Malformed link '$pair'; expected primary>associated."
                        continue
                    }

                    $primaryLogin = '{0}@{1}' -f $parts[0].Trim(), $connection.EmailDomain
                    $associatedLogin = '{0}@{1}' -f $parts[1].Trim(), $connection.EmailDomain

                    if (-not $userIdByLogin.ContainsKey($primaryLogin) -or
                        -not $userIdByLogin.ContainsKey($associatedLogin)) {
                        $message = "Link '$pair' names a user that does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # The call is made on the ASSOCIATED user and names the PRIMARY relationship,
                    # which reads backwards until you see it: you are setting "this user's
                    # mentor is X", not "X mentors this user". Getting it the wrong way round
                    # produces a link that exists and points the wrong way.
                    $null = Invoke-OktaRequest -Method PUT -Path (
                        "/api/v1/users/$($userIdByLogin[$associatedLogin])/linkedObjects/" +
                        "$($row.PrimaryName)/$($userIdByLogin[$primaryLogin])")

                    $linked += "$primaryLogin -> $associatedLogin"
                    $result.LinksCreated++
                }
            }

            $definitions.Add([PSCustomObject]@{
                Primary    = $row.PrimaryName
                Associated = $row.AssociatedName
                Links      = $linked
            })
        }
        catch {
            $message = "Failed to create linked object '$($row.PrimaryName)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Definitions = $definitions.ToArray()

    if ($PassThru) { return $result }
}
