function New-OktaGroup {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded Okta groups and assigns their members
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$GroupName,

        [Parameter()]
        [switch]$SkipMemberAssignment,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $csvPath = Join-Path -Path (Get-OktaDataPath) -ChildPath 'OktaGroups.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($GroupName) {
        $rows = @($rows | Where-Object { $GroupName -contains $_.Name })
        $unknown = @($GroupName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalGroups   = $rows.Count
        CreatedGroups = 0
        UpdatedGroups = 0
        MembersAdded  = 0
        Groups        = @()
        Errors        = @()
    }

    # One listing up front rather than a lookup per member. Membership is expressed as logins
    # in the CSV and ids in the API, and at eight users the whole mapping costs one call.
    $userIdByLogin = @{}
    if (-not $SkipMemberAssignment) {
        $seeded = @(Get-OktaSeededUser -Prefix $connection.Prefix `
            -EmailDomain $connection.EmailDomain)
        foreach ($user in $seeded) {
            $userIdByLogin[$user.profile.login] = $user.id
        }
    }

    $groups = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        # The display name is what goes to Okta, so the accented names actually reach the
        # directory. The CSV Name column stays ASCII and is the key that rules and member
        # lists refer to.
        $oktaName = '{0}-{1}' -f $connection.Prefix, $row.DisplayName
        $description = '{0} {1}' -f $row.Description, $connection.SeedMarker

        if (-not $PSCmdlet.ShouldProcess($oktaName, 'Create Okta group')) { continue }

        try {
            $existing = @(Invoke-OktaRequest -Method GET -Path '/api/v1/groups' `
                -Query @{ q = $oktaName; limit = 50 } -Paginate |
                Where-Object { $_.profile.name -eq $oktaName })

            if ($existing.Count -gt 0) {
                $group = Invoke-OktaRequest -Method PUT -Path "/api/v1/groups/$($existing[0].id)" `
                    -Body @{ profile = @{ name = $oktaName; description = $description } }
                $result.UpdatedGroups++
                Write-Verbose "Updated group $oktaName"
            }
            else {
                $group = Invoke-OktaRequest -Method POST -Path '/api/v1/groups' `
                    -Body @{ profile = @{ name = $oktaName; description = $description } }
                $result.CreatedGroups++
                Write-Verbose "Created group $oktaName"
            }

            $assigned = @()

            if (-not $SkipMemberAssignment) {
                foreach ($memberPrefix in @($row.Members -split ';' | Where-Object { $_ })) {
                    $login = '{0}@{1}' -f $memberPrefix, $connection.EmailDomain

                    if (-not $userIdByLogin.ContainsKey($login)) {
                        $message = "Group '$oktaName' lists '$login', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # PUT is idempotent here: adding a user who is already a member returns
                    # 204 rather than an error, so a re-run does not need a membership check.
                    $null = Invoke-OktaRequest -Method PUT `
                        -Path "/api/v1/groups/$($group.id)/users/$($userIdByLogin[$login])"
                    $assigned += $login
                    $result.MembersAdded++
                }
            }

            $groups.Add([PSCustomObject]@{
                Id         = $group.id
                Key        = $row.Name
                Name       = $oktaName
                Category   = $row.Category
                Assignment = $row.Assignment
                Members    = $assigned
            })
        }
        catch {
            $message = "Failed to create group '$oktaName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Groups = $groups.ToArray()

    Write-Verbose ("Groups: $($result.CreatedGroups) created, $($result.UpdatedGroups) updated, " +
        "$($result.MembersAdded) memberships, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
