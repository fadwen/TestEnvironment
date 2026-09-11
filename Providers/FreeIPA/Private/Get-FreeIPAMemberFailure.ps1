function Get-FreeIPAMemberFailure {
    <#
    .SYNOPSIS
        Reads the failures out of a membership call's result, one line each

    .DESCRIPTION
        FreeIPA's add-member and remove-member calls never fail as a whole. They answer with
        a count of completed changes and a 'failed' tree - member, then the kind (user, group,
        host), then a list of [name, reason] pairs - and a caller that reads only the count
        misses a member that was silently not added. This flattens that tree into
        'kind name: reason' lines, so each step can decide which reasons matter: 'already a
        member' is the normal answer on a re-run, and anything else is an error.

    .PARAMETER Outcome
        The envelope an add-member or remove-member call returned.

    .OUTPUTS
        System.String[]. One line per failure, or an empty array.

    .EXAMPLE
        PS> Get-FreeIPAMemberFailure -Outcome $outcome

        DESCRIPTION: Lists what a group_add_member call could not do
        OUTPUT: 'user jnino: This entry is already a member'
        USE CASE: Every step that assigns membership

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Outcome
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (-not $Outcome -or -not $Outcome.PSObject.Properties['failed'] -or -not $Outcome.failed) { return $lines.ToArray() }

    foreach ($relation in $Outcome.failed.PSObject.Properties) {
        if (-not $relation.Value) { continue }
        foreach ($kind in $relation.Value.PSObject.Properties) {
            foreach ($pair in @($kind.Value)) {
                $items = @($pair)
                # Built into a variable first: inside a method call's argument list the commas
                # of the format operator would be read as argument separators.
                $line = $null
                if ($items.Count -ge 2) { $line = '{0} {1}: {2}' -f $kind.Name, $items[0], $items[1] }
                elseif ($items.Count -eq 1) { $line = '{0} {1}' -f $kind.Name, $items[0] }
                if ($line) { $lines.Add($line) }
            }
        }
    }
    return $lines.ToArray()
}
