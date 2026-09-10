function New-EntraNamedLocation {
    <#
    .SYNOPSIS
        Creates the named locations Conditional Access policies condition on

    .DESCRIPTION
        Creates three named locations: a trusted IP range, an untrusted one, and a country
        location covering every usageLocation the seeded users carry.

        Every IP range is an IANA documentation block - 192.0.2.0/24, 198.51.100.0/24 and
        203.0.113.0/24, reserved by RFC 5737 precisely so they can appear in examples without
        belonging to anybody. That matters more than tidiness here. These locations are
        created in a tenant that is in real use, and a policy conditioned on a range somebody
        actually routes through is a policy that can lock a real person out of a real
        account.

        The trusted flag on the corporate range is not cosmetic. Several controls treat a
        trusted location as materially different from a merely known one - it is what
        suppresses risk-based prompting - so a lab that marks nothing trusted cannot
        reproduce the behaviour that flag causes.

        Country locations name ISO 3166-1 alpha-2 codes, and the seeded set is chosen to
        cover the usageLocation of every seeded user. A country condition that matches none
        of your test users tells you nothing when it fails to fire.

    .PARAMETER LocationKey
        Creates only the named locations, by their Key column. Defaults to all of them.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created locations

    .OUTPUTS
        EntraNamedLocation[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraNamedLocation

        DESCRIPTION: Creates all three named locations
        OUTPUT: None
        USE CASE: Called by New-EntraEnvironment before the policies that reference them

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraNamedLocation')]
    param(
        [Parameter()]
        [string[]]$LocationKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(Get-EntraSeedData -Name 'EntraNamedLocations')
    if ($LocationKey) {
        $definitions = @($definitions | Where-Object { $LocationKey -contains $_.Key })
        $missing = @($LocationKey | Where-Object { $definitions.Key -notcontains $_ })
        if ($missing) {
            Write-Error "No seed definition for named location key(s): $($missing -join ', ')" -ErrorAction Stop
            return
        }
    }

    # Entra places no uniqueness constraint on a named location's displayName, so without this
    # a re-run creates a second copy of every one of them.
    $existingByName = @{}
    foreach ($location in (Get-EntraSeededObject -Type NamedLocations -Connection $connection)) {
        $existingByName[$location.displayName] = $location
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.DisplayName

        Write-TestProgress -Activity 'Seeding named locations' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        if ($existingByName.ContainsKey($displayName)) {
            Write-Verbose "Named location '$displayName' already exists; reusing it"
            $created.Add([PSCustomObject]@{
                    PSTypeName   = 'EntraNamedLocation'
                    Key          = $definition.Key
                    Id           = $existingByName[$displayName].id
                    DisplayName  = $displayName
                    LocationType = $definition.LocationType
                    Values       = @($definition.Value -split ';' | Where-Object { $_ })
                    IsTrusted    = ($definition.LocationType -ne 'Country' -and [bool]::Parse($definition.IsTrusted))
                    Purpose      = $definition.Purpose
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create named location')) { continue }

        $values = @($definition.Value -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() })

        $body = if ($definition.LocationType -eq 'Country') {
            @{
                '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                displayName                       = $displayName
                countriesAndRegions               = $values
                # Stated explicitly rather than left to default, because the two behave
                # differently and the difference is invisible unless it is set on purpose: a
                # sign-in Entra cannot geolocate matches a location with this set and misses
                # one without it, however long the country list is.
                includeUnknownCountriesAndRegions = [bool]::Parse($definition.IncludeUnknown)
            }
        }
        else {
            @{
                '@odata.type' = '#microsoft.graph.ipNamedLocation'
                displayName   = $displayName
                isTrusted     = [bool]::Parse($definition.IsTrusted)
                ipRanges      = @(foreach ($range in $values) {
                        # The OData type is per-range, not per-location, and Graph rejects a
                        # v4 range declared as v6 rather than inferring it.
                        $type = if ($range -like '*:*') { '#microsoft.graph.iPv6CidrRange' } else { '#microsoft.graph.iPv4CidrRange' }
                        @{ '@odata.type' = $type; cidrAddress = $range }
                    })
            }
        }

        try {
            $location = Invoke-EntraRequest -Method POST -Path '/identity/conditionalAccess/namedLocations' -Body $body
        }
        catch {
            Write-Error "Failed to create named location '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName   = 'EntraNamedLocation'
                Key          = $definition.Key
                Id           = $location.id
                DisplayName  = $displayName
                LocationType = $definition.LocationType
                Values       = $values
                IsTrusted    = ($definition.LocationType -ne 'Country' -and [bool]::Parse($definition.IsTrusted))
                Purpose      = $definition.Purpose
            })

        Write-Verbose "Created named location '$displayName' ($($location.id))"
    }

    Write-TestProgress -Activity 'Seeding named locations' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
