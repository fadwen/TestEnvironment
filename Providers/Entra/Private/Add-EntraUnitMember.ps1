function Add-EntraUnitMember {
    <#
    .SYNOPSIS
        Adds created objects to their administrative unit, in batches

    .DESCRIPTION
        Every object this module creates is placed in the administrative unit for its class,
        and that membership is what teardown treats as proof of ownership. So this is not
        bookkeeping: an object created and not placed is an object that a later teardown will
        have to fall back to a name match to find.

        Membership is added in batches, because at AD parity this is eleven hundred references
        and one call each would dominate the run.

        A failure here is a warning rather than an error. The object exists either way, and it
        still carries the name prefix and its own marker, so teardown can still find it - just
        by the weaker route. Failing the seed over it would leave the object behind anyway,
        with less written down about it.

    .PARAMETER UnitId
        Object id of the administrative unit

    .PARAMETER ObjectId
        Object ids to place in it

    .PARAMETER Activity
        Progress bar title

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER Connection
        Connection to use instead of the module's active one

    .OUTPUTS
        System.Int32, the number of objects successfully placed.

    .EXAMPLE
        PS> Add-EntraUnitMember -UnitId $unit.Id -ObjectId $createdUserIds

        DESCRIPTION: Places every created user in the Users unit
        OUTPUT: 305
        USE CASE: Called at the end of each seeding step

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UnitId,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ObjectId,

        [Parameter()]
        [string]$Activity = 'Placing objects in their administrative unit',

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }

    $ids = @($ObjectId | Where-Object { $_ })
    if ($ids.Count -eq 0) { return 0 }

    $requests = foreach ($id in $ids) {
        [PSCustomObject]@{
            Reference = $id
            Method    = 'POST'
            # The $ref form, so the object is referenced rather than created inside the unit.
            Url       = "/directory/administrativeUnits/$UnitId/members/`$ref"
            Body      = @{ '@odata.id' = "$($Connection.GraphBaseUri)/v1.0/directoryObjects/$id" }
        }
    }

    # -RetryOnNotFound is not optional here. These references name objects created seconds
    # earlier, and Graph rejects a reference to an object the handling replica has not seen
    # yet with a 404. Verified live: without it a first pass placed 72 of 305 users and
    # reported the other 233 as failures.
    $results = @(Invoke-EntraBatch -Request $requests -Connection $Connection -RetryOnNotFound `
            -Activity $Activity -ShowProgress:$ShowProgress)

    $placed = @($results | Where-Object { $_.Success })
    $failed = @($results | Where-Object { -not $_.Success })

    # A repeat run finds the object already in the unit. That is the expected state when
    # re-seeding over an existing environment, not a failure worth reporting.
    #
    # Graph reports an existing administrative unit membership as "A conflicting object with
    # one or more of the specified property values is present in the directory", NOT with the
    # "already exist" wording it uses for a duplicate group member. Matching only the latter
    # made a fully successful placement report zero placed and 305 failed.
    $duplicate = 'already exist|added object references already exist|A conflicting object'
    $alreadyThere = @($failed | Where-Object { $_.Error -match $duplicate })
    $genuine = @($failed | Where-Object { $_.Error -notmatch $duplicate })

    if ($genuine.Count -gt 0) {
        Write-Warning ("$($genuine.Count) object(s) could not be placed in the administrative unit. They still " +
            "carry the name prefix, so teardown will find them by the weaker route. First error: $($genuine[0].Error)")
    }
    if ($alreadyThere.Count -gt 0) {
        Write-Verbose "$($alreadyThere.Count) object(s) were already in the unit"
    }

    return ($placed.Count + $alreadyThere.Count)
}
