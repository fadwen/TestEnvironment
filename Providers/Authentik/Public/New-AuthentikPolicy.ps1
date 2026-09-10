function New-AuthentikPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded expression policies and binds them to the seeded applications
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [switch]$SkipBinding,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-AuthentikDataPath) -ChildPath 'AuthentikPolicies.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($PolicyName) {
        $rows = @($rows | Where-Object { $PolicyName -contains $_.Name })
        $unknown = @($PolicyName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalPolicies   = $rows.Count
        CreatedPolicies = 0
        UpdatedPolicies = 0
        BindingsCreated = 0
        Policies        = @()
        Errors          = @()
    }

    $existingByName = @{}
    foreach ($existing in (Get-AuthentikSeededObject -Type Policies -Connection $connection)) {
        $existingByName[[string]$existing.name] = $existing
    }

    $targetBySlug = @{}
    if (-not $SkipBinding) {
        foreach ($application in (Get-AuthentikSeededObject -Type Applications -Connection $connection)) {
            $targetBySlug[[string]$application.slug] = [string]$application.pbm_uuid
        }
    }

    $policies = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}{1}' -f $marker.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Authentik expression policy')) { continue }

        try {
            $expression = $row.Expression.Replace('{prefix}', $marker.Prefix).Replace('`n', "`n")
            $body = @{ name = $name; expression = $expression; execution_logging = $false }

            $policy = $null
            if ($existingByName.ContainsKey($name)) {
                $policy = Invoke-AuthentikRequest -Method PATCH -Path "/policies/expression/$($existingByName[$name].pk)/" -Body $body -Connection $connection
                $result.UpdatedPolicies++
                Write-Verbose "Updated policy $name"
            }
            else {
                $policy = Invoke-AuthentikRequest -Method POST -Path '/policies/expression/' -Body $body -Connection $connection
                $result.CreatedPolicies++
                Write-Verbose "Created policy $name"
            }

            $boundTo = $null
            $bound = $false
            if (-not $SkipBinding) {
                $targetSlug = '{0}-{1}' -f $marker.SlugPrefix, $row.Target
                if (-not $targetBySlug.ContainsKey($targetSlug)) {
                    $message = "Policy '$name' targets application '$targetSlug', which does not exist. Created unbound."
                    $result.Errors += $message
                    Write-Warning $message
                }
                else {
                    $target = $targetBySlug[$targetSlug]
                    $existingBindings = @(Invoke-AuthentikRequest -Method GET -Path '/policies/bindings/' `
                            -Query @{ policy = [string]$policy.pk; target = $target } -Connection $connection -Paginate)
                    if ($existingBindings.Count -eq 0) {
                        $null = Invoke-AuthentikRequest -Method POST -Path '/policies/bindings/' -Connection $connection -Body @{
                            policy  = [string]$policy.pk
                            target  = $target
                            order   = [int]$row.Order
                            enabled = ($row.Enabled -eq 'TRUE')
                            negate  = ($row.Negate -eq 'TRUE')
                        }
                        $result.BindingsCreated++
                    }
                    $boundTo = $targetSlug
                    $bound = $true
                }
            }

            $policies.Add([PSCustomObject]@{
                    Id      = [string]$policy.pk
                    Key     = $row.Name
                    Name    = $name
                    Target  = $boundTo
                    Bound   = $bound
                    Order   = [int]$row.Order
                    Enabled = ($row.Enabled -eq 'TRUE')
                })
        }
        catch {
            $message = "Failed to create policy '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Policies = $policies.ToArray()

    Write-Verbose ("Policies: $($result.CreatedPolicies) created, $($result.UpdatedPolicies) updated, " +
        "$($result.BindingsCreated) bindings, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
