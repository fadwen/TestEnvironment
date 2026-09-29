function New-OneLoginCustomAttribute {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the custom user fields the seed needs, including its ownership marker
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Shortname,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OneLoginConnection

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginCustomAttributes.csv') -Encoding UTF8)
    if ($Shortname) { $rows = @($rows | Where-Object { $Shortname -contains $_.Shortname }) }

    $existing = @{}
    foreach ($field in @(Invoke-OneLoginRequest -Method GET -Path 'users/custom_attributes' -Connection $connection | ForEach-Object { $_ })) {
        if ($null -ne $field -and $field.shortname) { $existing[[string]$field.shortname] = $field }
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $reused = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        if ($existing.ContainsKey($row.Shortname)) {
            # Left as it is. The field is a name and a shortname and nothing else, so there is
            # nothing to converge, and replacing it would drop the value every seeded user holds.
            Write-Verbose "Custom field $($row.Shortname) already exists; reusing it"
            $reused.Add([PSCustomObject]@{ Shortname = $row.Shortname; Id = $existing[$row.Shortname].id })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($row.Shortname, 'Create OneLogin custom user field')) { continue }

        try {
            $result = Invoke-OneLoginRequest -Method POST -Path 'users/custom_attributes' `
                -Body @{ user_field = @{ name = $row.Name; shortname = $row.Shortname } } -Connection $connection
            $created.Add([PSCustomObject]@{ Shortname = $row.Shortname; Id = $result.id })
            Write-Verbose "Created custom field $($row.Shortname)"
        }
        catch {
            $errors.Add("Could not create custom field $($row.Shortname): $($_.Exception.Message)")
            Write-Warning "Could not create custom field $($row.Shortname): $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            TotalAttributes   = @($rows).Count
            CreatedAttributes = $created.Count
            ReusedAttributes  = $reused.Count
            Attributes        = (@($created) + @($reused))
            Errors            = $errors.ToArray()
        }
    }
}
