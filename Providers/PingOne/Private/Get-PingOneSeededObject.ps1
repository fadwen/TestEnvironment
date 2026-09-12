function Get-PingOneSeededObject {
    <#
    .SYNOPSIS
        Returns the objects of one type that this module can prove it created

    .DESCRIPTION
        Teardown's only source of truth. Nothing is deleted for merely matching a name, and this
        is where that promise is kept.

        Proof differs by type, because PingOne gives each type a different place to hold it:

        - Populations, groups, applications and resources carry the seed tag in their
          description, and their name must also carry the prefix. Both are required: the tag
          alone could be pasted into a real object's description by accident, and the prefix
          alone is exactly the name-matching this module refuses to do.
        - Users are proved by the population first. A user in a seeded population is ours.
          The custom attribute is the fallback, for a user moved out of a seeded population by
          hand, and on its own it is enough, because nothing but this module writes that
          attribute - the module creates it.
        - The custom attributes themselves are proved by name, and only the names this
          provider's data file declares. There is no description to check, and a custom
          attribute this module did not declare is left alone however it is named.

        PingOne's own applications and resources are refused outright by type, whatever their
        description says, so a platform application that somehow picked up the tag can never
        be selected for deletion.

        The seed marker contains no wildcard characters, but it is tested with Contains rather
        than -like anyway, so a future marker with brackets in it cannot silently match nothing.

    .PARAMETER Type
        Which kind of object to return.

    .PARAMETER Connection
        The connection to use. Defaults to the session's.

    .OUTPUTS
        The PingOne objects this module owns, of the requested type.

    .EXAMPLE
        PS> Get-PingOneSeededObject -Type Users

        DESCRIPTION: Lists the seeded people, by population and then by tag
        OUTPUT: User objects
        USE CASE: Called by Remove-PingOneEnvironment and Get-PingOneEnvironmentReport

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Populations', 'Users', 'Groups', 'Applications', 'Resources', 'Attributes')]
        [string]$Type,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-PingOneConnection }

    $marker = Get-PingOneSeedMarker -Prefix $Connection.Prefix
    $tag = $marker.Tag
    $prefix = $marker.Prefix

    # Tag in the description AND the prefix on the name. Either alone is not proof.
    $isTagged = {
        param($object)
        $description = [string]$object.description
        $name = [string]$object.name
        return ($description.Contains($tag) -and
            $name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))
    }

    switch ($Type) {
        'Populations' {
            return @(Invoke-PingOneRequest -Method GET -Path 'populations' -Paginate -Connection $Connection |
                    Where-Object { & $isTagged $_ })
        }

        'Groups' {
            return @(Invoke-PingOneRequest -Method GET -Path 'groups' -Paginate -Connection $Connection |
                    Where-Object { & $isTagged $_ })
        }

        'Resources' {
            return @(Invoke-PingOneRequest -Method GET -Path 'resources' -Paginate -Connection $Connection |
                    Where-Object { $script:PingOnePlatformResourceType -notcontains $_.type } |
                    Where-Object { & $isTagged $_ })
        }

        'Applications' {
            return @(Invoke-PingOneRequest -Method GET -Path 'applications' -Paginate -Connection $Connection |
                    Where-Object { $script:PingOnePlatformApplicationType -notcontains $_.type } |
                    Where-Object { & $isTagged $_ })
        }

        'Users' {
            $seededPopulationIds = @{}
            foreach ($population in (Get-PingOneSeededObject -Type Populations -Connection $Connection)) {
                $seededPopulationIds[[string]$population.id] = $true
            }

            $claimed = @{}
            $result = [System.Collections.Generic.List[object]]::new()

            # By population first. Filtering server-side keeps a large environment from being
            # read whole just to find the seeded few hundred.
            foreach ($populationId in $seededPopulationIds.Keys) {
                $filter = 'population.id eq "{0}"' -f $populationId
                foreach ($user in (Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $Connection -Query @{ filter = $filter })) {
                    if (-not $claimed.ContainsKey([string]$user.id)) {
                        $claimed[[string]$user.id] = $true
                        $result.Add($user)
                    }
                }
            }

            # Then by the tag, for a seeded user moved out of a seeded population by hand.
            #
            # Only when the attribute exists. PingOne refuses a filter naming an attribute that is
            # not in the schema, with HTTP 400 REQUEST_FAILED - a code broad enough that ignoring
            # it would also hide a genuine failure. The attribute is absent on a fresh environment
            # and again after teardown removes it last, so a report before the first seed, or a
            # teardown run twice, used to throw here. Asking the schema first is deterministic and
            # needs no guess about which error code means "no such attribute".
            $attributeName = $script:PingOneSeedAttributeName
            $attributeExists = $false
            foreach ($schema in (Invoke-PingOneRequest -Method GET -Path 'schemas' -Paginate -Connection $Connection)) {
                $match = @(Invoke-PingOneRequest -Method GET -Path "schemas/$($schema.id)/attributes" -Paginate -Connection $Connection |
                        Where-Object { $_.name -eq $attributeName })
                if ($match) { $attributeExists = $true; break }
            }

            $tagged = @()
            if ($attributeExists) {
                $filter = '{0} eq "{1}"' -f $attributeName, $tag
                # Nulls filtered out explicitly, so no path can ever hand teardown a user with no
                # id - which would become "DELETE users/" with nothing after the slash.
                $tagged = @(Invoke-PingOneRequest -Method GET -Path 'users' -Paginate -Connection $Connection `
                        -Query @{ filter = $filter } | Where-Object { $null -ne $_ -and $_.id })
            }
            foreach ($user in $tagged) {
                if (-not $claimed.ContainsKey([string]$user.id)) {
                    $claimed[[string]$user.id] = $true
                    $result.Add($user)
                }
            }

            return $result.ToArray()
        }

        'Attributes' {
            $declared = @(Import-Csv -LiteralPath (Join-Path (Get-PingOneDataPath) 'PingOneProfileAttributes.csv') -Encoding UTF8).Name

            $schemas = @(Invoke-PingOneRequest -Method GET -Path 'schemas' -Paginate -Connection $Connection)
            $result = [System.Collections.Generic.List[object]]::new()
            foreach ($schema in $schemas) {
                foreach ($attribute in (Invoke-PingOneRequest -Method GET -Path "schemas/$($schema.id)/attributes" -Paginate -Connection $Connection)) {
                    # CUSTOM only. A CORE or STANDARD attribute is the platform's, whatever it
                    # is called, and the name check below would otherwise be the only guard.
                    if ($attribute.schemaType -ne 'CUSTOM') { continue }
                    if ($declared -notcontains [string]$attribute.name) { continue }
                    $attribute | Add-Member -NotePropertyName SchemaId -NotePropertyValue $schema.id -Force
                    $result.Add($attribute)
                }
            }
            return $result.ToArray()
        }
    }
}
