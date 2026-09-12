function Remove-PingOneEnvironment {
    <#
    .SYNOPSIS
        Removes every object this module created in a PingOne environment, proving ownership first

    .DESCRIPTION
        Reached through Remove-TestEnvironment once a PingOne connection is active.

        Nothing is deleted for matching a name. Every object is selected by
        Get-PingOneSeededObject, which requires the seed tag in the description AND the prefix
        on the name for the types that have a description, asks the seeded populations for
        their users before falling back to the tag, and refuses PingOne's own applications and
        resources by type however they are described.

        The order is the reverse of the seed, and each position is forced by what PingOne will
        and will not delete:

        1. Applications   - their grants go with them, and they reference groups and resources.
        2. Resources      - their scopes go with them.
        3. Users          - their group memberships go with them.
        4. Groups         - no longer referenced by any application.
        5. Populations    - only empty populations can be deleted, so the users go first.
        6. Attributes     - last, because PingOne refuses to delete a custom attribute while
                            any user still holds a value in it.

        The confirmation is asked once, for the whole run, in the body of the function, and not in
        a begin{} block: a return inside begin{} ends that block and nothing else, so a refusal
        there would not stop the deletion. A refusal here stops the function. A session that cannot answer the prompt is refused
        too, so an automated teardown has to pass -Force.

        -WhatIf always wins over -Force. -Force lowers the confirmation preference and nothing
        else; every deletion still goes through ShouldProcess, so "-Force -WhatIf" deletes
        nothing and prints a line for every object it would have removed.

    .PARAMETER Keep
        Object types to leave in place.

    .PARAMETER Force
        Remove without asking for confirmation. Required for any unattended teardown.

    .PARAMETER PassThru
        Return the results object.

    .OUTPUTS
        PSCustomObject describing what was removed, when -PassThru is used.

    .EXAMPLE
        PS> Remove-TestEnvironment -WhatIf

        DESCRIPTION: Lists everything teardown would remove, removing nothing
        OUTPUT: A What if: line per object
        USE CASE: Checking ownership before deleting anything in an environment you care about

    .EXAMPLE
        PS> Remove-TestEnvironment -Force -Keep Attributes -PassThru

        DESCRIPTION: Removes everything except the custom attributes, unattended
        OUTPUT: The results object
        USE CASE: Tearing down between runs while keeping the schema, so the next seed is faster

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-PingOneEnvironment
        Get-PingOneEnvironmentReport
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The teardown summary is written for the person watching the run; the result object carries the same data for scripts.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Applications', 'Resources', 'Users', 'Groups', 'Populations', 'Attributes')]
        [string[]]$Keep = @(),

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting Remove-PingOneEnvironment - CorrelationId: $correlationId"

    $connection = Get-PingOneConnection

    $removed = [ordered]@{
        Applications = 0
        Resources    = 0
        Users        = 0
        Groups       = 0
        Populations  = 0
        Attributes   = 0
    }
    $errors = [System.Collections.Generic.List[string]]::new()

    $buildResult = {
        param([bool]$Cancelled)
        [PSCustomObject]@{
            CorrelationId   = $correlationId
            EnvironmentId   = $connection.EnvironmentId
            EnvironmentName = $connection.EnvironmentName
            Cancelled       = $Cancelled
            Removed         = [PSCustomObject]$removed
            TotalRemoved    = ($removed.Values | Measure-Object -Sum).Sum
            Errors          = $errors.ToArray()
        }
    }

    # One confirmation for the run, asked here in the body where a refusal actually stops the
    # function. Skipped under -WhatIf, because a preview changes nothing and demanding an answer
    # before showing what would happen made -WhatIf unusable from anything non-interactive.
    if (-not $WhatIfPreference) {
        $question = ("Remove every object this module created in PingOne environment '{0}' ({1})?" -f
            $connection.EnvironmentName, $connection.EnvironmentId)

        $confirmed = $Force
        if (-not $confirmed) {
            try {
                $confirmed = $PSCmdlet.ShouldContinue($question, 'Remove PingOne test environment')
            }
            catch {
                # A session with no host to answer throws rather than returning false. That is a
                # refusal, not an agreement: an unattended teardown has to say -Force.
                Write-Verbose "The confirmation could not be asked: $($_.Exception.Message)"
                $confirmed = $false
            }
        }

        if (-not $confirmed) {
            Write-Host 'Teardown cancelled. Nothing was removed. Pass -Force to remove without being asked.'
            if ($PassThru) { return (& $buildResult $true) }
            return
        }

        # Asked once; every deletion below still passes through ShouldProcess, so -WhatIf is
        # never defeated by this.
        $ConfirmPreference = 'None'
    }

    Write-TestMessage -Message ("PingOne Test Environment Teardown ({0}, {1})" -f
        $connection.EnvironmentName, $connection.EnvironmentId) -Type Header

    $delete = {
        param([string]$Type, [string]$Path, [string]$Label)
        if (-not $PSCmdlet.ShouldProcess($Label, "Delete PingOne $Type")) { return }
        try {
            $null = Invoke-PingOneRequest -Method DELETE -Path $Path -Connection $connection -IgnoreError 'NOT_FOUND'
            $removed[$Type]++
        }
        catch {
            $errors.Add("Could not delete $Type '${Label}': $($_.Exception.Message)")
            Write-Warning "Could not delete $Type '${Label}': $($_.Exception.Message)"
        }
    }

    # --- 1. Applications -------------------------------------------------------------------
    if ($Keep -notcontains 'Applications') {
        Write-Host 'Removing applications'
        foreach ($application in (Get-PingOneSeededObject -Type Applications -Connection $connection)) {
            & $delete 'Applications' "applications/$($application.id)" $application.name
        }
    }

    # --- 2. Resources ----------------------------------------------------------------------
    if ($Keep -notcontains 'Resources') {
        Write-Host 'Removing resources'
        foreach ($resource in (Get-PingOneSeededObject -Type Resources -Connection $connection)) {
            & $delete 'Resources' "resources/$($resource.id)" $resource.name
        }
    }

    # --- 3. Users --------------------------------------------------------------------------
    if ($Keep -notcontains 'Users') {
        Write-Host 'Removing users'
        foreach ($user in (Get-PingOneSeededObject -Type Users -Connection $connection)) {
            & $delete 'Users' "users/$($user.id)" $user.username
        }
    }

    # --- 4. Groups -------------------------------------------------------------------------
    if ($Keep -notcontains 'Groups') {
        Write-Host 'Removing groups'
        foreach ($group in (Get-PingOneSeededObject -Type Groups -Connection $connection)) {
            & $delete 'Groups' "groups/$($group.id)" $group.name
        }
    }

    # --- 5. Populations --------------------------------------------------------------------
    # Only an empty population can be deleted. Keeping users while removing populations is
    # therefore refused up front rather than failing object by object.
    if ($Keep -notcontains 'Populations') {
        if ($Keep -contains 'Users') {
            $errors.Add('Populations were not removed: -Keep Users leaves them holding people, and PingOne only deletes an empty population.')
        }
        else {
            Write-Host 'Removing populations'
            foreach ($population in (Get-PingOneSeededObject -Type Populations -Connection $connection)) {
                & $delete 'Populations' "populations/$($population.id)" $population.name
            }
        }
    }

    # --- 6. Attributes ---------------------------------------------------------------------
    # Last. PingOne refuses to delete a custom attribute while any user holds a value in it.
    if ($Keep -notcontains 'Attributes') {
        if ($Keep -contains 'Users') {
            $errors.Add('Custom attributes were not removed: -Keep Users leaves people holding values in them.')
        }
        else {
            Write-Host 'Removing custom attributes'
            foreach ($attribute in (Get-PingOneSeededObject -Type Attributes -Connection $connection)) {
                & $delete 'Attributes' "schemas/$($attribute.SchemaId)/attributes/$($attribute.id)" $attribute.name
            }
        }
    }

    $result = & $buildResult $false

    Write-TestMessage -Message 'Teardown Summary' -Type Header
    Write-Host ("Objects removed: {0}" -f $result.TotalRemoved)
    foreach ($type in $removed.Keys) { Write-Host ("  {0,-13} {1}" -f $type, $removed[$type]) }
    foreach ($message in $errors) { Write-Host ("  ! {0}" -f $message) }

    if ($PassThru) { return $result }
}
