function New-OktaGroupRule {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the group rules that populate the automatic groups
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RuleName,

        [Parameter()]
        [switch]$SkipActivation,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaConnection

    $dataPath = Get-OktaDataPath
    $rows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaGroupRules.csv') -Encoding UTF8)
    $groupRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaGroups.csv') -Encoding UTF8)

    if ($RuleName) {
        $rows = @($rows | Where-Object { $RuleName -contains $_.Name })
        $unknown = @($RuleName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No rule definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules     = $rows.Count
        CreatedRules   = 0
        UpdatedRules   = 0
        ActivatedRules = 0
        Rules          = @()
        Errors         = @()
    }

    # The CSV names a target by its ASCII key; Okta knows it by its prefixed display name.
    $oktaNameByKey = @{}
    foreach ($groupRow in $groupRows) {
        $oktaNameByKey[$groupRow.Name] = '{0}-{1}' -f $connection.Prefix, $groupRow.DisplayName
    }

    $existingGroups = @(Get-OktaSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)
    $groupIdByName = @{}
    foreach ($group in $existingGroups) { $groupIdByName[$group.profile.name] = $group.id }

    $existingRules = @(Invoke-OktaRequest -Method GET -Path '/api/v1/groups/rules' `
        -Query @{ limit = 200 } -Paginate)

    $rules = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $ruleFullName = '{0}-Rule-{1}' -f $connection.Prefix, $row.Name
        $targetOktaName = $oktaNameByKey[$row.TargetGroup]

        if (-not $targetOktaName -or -not $groupIdByName.ContainsKey($targetOktaName)) {
            $message = ("Rule '$ruleFullName' targets group '$($row.TargetGroup)', which does not " +
                'exist. Run New-OktaGroup first. Skipped.')
            $result.Errors += $message
            Write-Warning $message
            continue
        }

        $activate = (-not $SkipActivation) -and ([bool]::Parse($row.Activate))

        if (-not $PSCmdlet.ShouldProcess($ruleFullName, 'Create Okta group rule')) { continue }

        $body = @{
            type       = 'group_rule'
            name       = $ruleFullName
            conditions = @{
                people     = @{
                    users  = @{ exclude = @() }
                    groups = @{ exclude = @() }
                }
                expression = @{
                    value = $row.Expression
                    type  = 'urn:okta:expression:1.0'
                }
            }
            actions    = @{
                assignUserToGroups = @{ groupIds = @($groupIdByName[$targetOktaName]) }
            }
        }

        try {
            $existing = @($existingRules | Where-Object { $_.name -eq $ruleFullName })

            if ($existing.Count -gt 0) {
                $ruleId = $existing[0].id

                # Okta refuses to modify an active rule. Deactivating first is not optional,
                # and doing it unconditionally is simpler than reading the current status and
                # costs one call that would usually be made anyway.
                try {
                    $null = Invoke-OktaRequest -Method POST `
                        -Path "/api/v1/groups/rules/$ruleId/lifecycle/deactivate"
                }
                catch {
                    Write-Verbose "Rule $ruleFullName was already inactive."
                }

                $rule = Invoke-OktaRequest -Method PUT -Path "/api/v1/groups/rules/$ruleId" -Body $body
                $result.UpdatedRules++
            }
            else {
                $rule = Invoke-OktaRequest -Method POST -Path '/api/v1/groups/rules' -Body $body
                $result.CreatedRules++
            }

            if ($activate) {
                $null = Invoke-OktaRequest -Method POST `
                    -Path "/api/v1/groups/rules/$($rule.id)/lifecycle/activate"
                $result.ActivatedRules++
            }

            $rules.Add([PSCustomObject]@{
                Id          = $rule.id
                Name        = $ruleFullName
                TargetGroup = $targetOktaName
                Expression  = $row.Expression
                Active      = $activate
            })
        }
        catch {
            $message = "Failed to create rule '$ruleFullName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Rules = $rules.ToArray()

    if ($result.ActivatedRules -gt 0) {
        Write-Verbose ('Group rules evaluate asynchronously; membership will appear shortly, and ' +
            'only for active users.')
    }

    if ($PassThru) { return $result }
}
