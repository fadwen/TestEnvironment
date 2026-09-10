function New-AuthentikBinding {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded group, user and policy bindings from Data\AuthentikBindings.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Target,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikBindings.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($Target) {
        $rows = @($rows | Where-Object { $Target -contains $_.Target })
        $unknown = @($Target | Where-Object { $rows.Target -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalBindings    = $rows.Count
        CreatedBindings  = 0
        ExistingBindings = 0
        Bindings         = @()
        Errors           = @()
    }

    # Every target and subject the CSV can name, resolved once. Each map is keyed the way the
    # CSV writes it, so a row never sees a UUID.
    $targets = @{}
    $subjects = @{}

    foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
        $key = $application.slug.Substring($marker.SlugPrefix.Length + 1)
        $targets["app:$key"] = [string]$application.pbm_uuid
    }
    foreach ($entitlement in (Get-AuthentikSeededObject -Type Entitlements -Connection $connection)) {
        if ($entitlement.attributes.PSObject.Properties['labKey']) { $targets["entitlement:$($entitlement.attributes.labKey)"] = [string]$entitlement.pbm_uuid }
    }
    foreach ($rule in (Get-AuthentikSeededObject -Type NotificationRules -Connection $connection)) {
        # A notification rule is itself a policy-binding model, so its pk is the target.
        $targets["rule:$($rule.name.Substring($marker.Prefix.Length))"] = [string]$rule.pk
    }
    foreach ($group in (Get-AuthentikSeededObject -Type Groups -Connection $connection)) {
        if ($group.attributes.PSObject.Properties['labKey']) { $subjects["group:$($group.attributes.labKey)"] = @{ group = [string]$group.pk } }
    }
    foreach ($user in (Get-AuthentikSeededObject -Type Users -Connection $connection)) {
        $subjects["user:$($user.username)"] = @{ user = [int]$user.pk }
    }
    foreach ($policy in (Get-AuthentikSeededObject -Type Policies -Connection $connection)) {
        $subjects["policy:$($policy.name.Substring($marker.Prefix.Length))"] = @{ policy = [string]$policy.pk }
    }

    $existingByTarget = @{}
    $bindings = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $label = '{0} -> {1}' -f $row.Subject, $row.Target

        if (-not $PSCmdlet.ShouldProcess($label, 'Create Authentik policy binding')) { continue }

        try {
            if (-not $targets.ContainsKey($row.Target)) {
                $message = "Binding '$label' names target '$($row.Target)', which does not exist. Skipped."
                $result.Errors += $message
                Write-Warning $message
                continue
            }
            if (-not $subjects.ContainsKey($row.Subject)) {
                $message = "Binding '$label' names subject '$($row.Subject)', which does not exist. Skipped."
                $result.Errors += $message
                Write-Warning $message
                continue
            }

            $targetUuid = $targets[$row.Target]
            $subject = $subjects[$row.Subject]

            if (-not $existingByTarget.ContainsKey($targetUuid)) {
                $existingByTarget[$targetUuid] = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                        -Query @{ target = $targetUuid } -Connection $connection -Paginate)
            }
            $duplicate = @($existingByTarget[$targetUuid] | Where-Object {
                    ($subject.ContainsKey('group') -and [string]$_.group -eq $subject.group) -or
                    ($subject.ContainsKey('user') -and [string]$_.user -eq [string]$subject.user) -or
                    ($subject.ContainsKey('policy') -and [string]$_.policy -eq $subject.policy)
                })

            $binding = $null
            if ($duplicate.Count -gt 0) {
                $binding = $duplicate[0]
                $result.ExistingBindings++
                Write-Verbose "Binding $label already exists"
            }
            else {
                $body = @{
                    target  = $targetUuid
                    order   = [int]$row.Order
                    enabled = ($row.Enabled -eq 'TRUE')
                    negate  = ($row.Negate -eq 'TRUE')
                }
                foreach ($k in $subject.Keys) { $body[$k] = $subject[$k] }
                $binding = Invoke-AuthentikRequest -Method POST -Path '/policies/bindings/' -Body $body -Connection $connection
                $result.CreatedBindings++
                Write-Verbose "Created binding $label"
            }

            $bindings.Add([PSCustomObject]@{
                    Id      = [string]$binding.pk
                    Target  = $row.Target
                    Subject = $row.Subject
                    Order   = [int]$row.Order
                    Enabled = ($row.Enabled -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create binding '$label': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Bindings = $bindings.ToArray()

    Write-Verbose ("Bindings: $($result.CreatedBindings) created, $($result.ExistingBindings) existing, " +
        "$($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
