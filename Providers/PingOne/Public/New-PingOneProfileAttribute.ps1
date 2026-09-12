function New-PingOneProfileAttribute {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the custom user schema attributes the seed needs, including its ownership marker
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Name,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneProfileAttributes.csv') -Encoding UTF8)
    if ($Name) { $rows = @($rows | Where-Object { $Name -contains $_.Name }) }

    $schema = @(Invoke-PingOneRequest -Method GET -Path 'schemas' -Paginate -Connection $connection |
            Where-Object { $_.name -eq 'User' })
    if (-not $schema) {
        # Every environment has exactly one user schema, but its name has changed before.
        $schema = @(Invoke-PingOneRequest -Method GET -Path 'schemas' -Paginate -Connection $connection)
    }
    $schemaId = $schema[0].id

    $existing = @{}
    foreach ($attribute in (Invoke-PingOneRequest -Method GET -Path "schemas/$schemaId/attributes" -Paginate -Connection $connection)) {
        $existing[[string]$attribute.name] = $attribute
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($row in $rows) {
        if ($existing.ContainsKey($row.Name)) {
            # Left alone rather than replaced: replacing an attribute drops the value every
            # seeded user holds in it, which would orphan the whole directory from its marker.
            Write-Verbose "Attribute $($row.Name) already exists; leaving it as it is"
            $skipped.Add($row.Name)
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($row.Name, 'Create PingOne user attribute')) { continue }

        $body = @{
            name        = $row.Name
            displayName = $row.DisplayName
            description = $row.Purpose
            type        = $row.Type
            unique      = [bool]::Parse($row.Unique)
            multiValued = [bool]::Parse($row.MultiValued)
            required    = [bool]::Parse($row.Required)
            enabled     = $true
        }

        try {
            $result = Invoke-PingOneRequest -Method POST -Path "schemas/$schemaId/attributes" -Body $body -Connection $connection
            $created.Add([PSCustomObject]@{ Name = $row.Name; Id = $result.id; Type = $row.Type })
            Write-Verbose "Created attribute $($row.Name)"
        }
        catch {
            $errors.Add("Could not create attribute $($row.Name): $($_.Exception.Message)")
            Write-Warning "Could not create attribute $($row.Name): $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            SchemaId            = $schemaId
            TotalAttributes     = @($rows).Count
            CreatedAttributes   = $created.Count
            ExistingAttributes  = $skipped.Count
            Attributes          = $created.ToArray()
            Errors              = $errors.ToArray()
        }
    }
}
