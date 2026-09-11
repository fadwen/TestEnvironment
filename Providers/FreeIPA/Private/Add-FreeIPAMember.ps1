function Add-FreeIPAMember {
    <#
    .SYNOPSIS
        Adds members to a FreeIPA object through one of its add-member methods, tolerating repeats

    .DESCRIPTION
        Every FreeIPA object that holds members - a group, a netgroup, an HBAC rule, a sudo
        rule, a role, a delegation target - takes them through a method of the same shape:
        the object's name as the argument and one list per member kind in the options. The
        call never fails as a whole; it answers with a count of completed changes and a
        'failed' tree, and 'This entry is already a member' in that tree is the normal
        answer on a re-run. This makes the call once for every kind that has members, drops
        the repeats, and returns what is left as errors the step records, so that each step
        does not carry the same twenty lines.

    .PARAMETER Method
        The add-member method: group_add_member, hbacrule_add_user, sudorule_add_runasuser
        and so on.

    .PARAMETER Name
        The object the members join.

    .PARAMETER Members
        A hashtable of kind to names: @{ user = @('jnino'); group = @('zz-test-all-staff') }.
        Kinds with no names are dropped, and nothing is sent when none remain.

    .PARAMETER Connection
        The connection to send through. Defaults to the active one.

    .OUTPUTS
        PSCustomObject with Completed and Errors.

    .EXAMPLE
        PS> Add-FreeIPAMember -Method 'hbacrule_add_user' -Name 'zz-test-staff-bastion' -Members @{ group = @('zz-test-all-staff') }

        DESCRIPTION: Adds a group to an HBAC rule's who-clause
        OUTPUT: Completed 1, no errors
        USE CASE: Every step that assigns membership

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9_]*$')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Members,

        [Parameter()]
        [hashtable]$Connection
    )

    $options = @{}
    foreach ($kind in $Members.Keys) {
        $names = @($Members[$kind] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($names.Count -gt 0) { $options[[string]$kind] = [object[]]$names }
    }

    $result = [PSCustomObject]@{ Completed = 0; Errors = @() }
    if ($options.Count -eq 0) { return $result }

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }
    $outcome = Invoke-FreeIPARequest -Method $Method -Arguments $Name -Options $options -Connection $Connection
    if ($outcome -and $outcome.PSObject.Properties['completed']) { $result.Completed = [int]$outcome.completed }
    foreach ($failure in @(Get-FreeIPAMemberFailure -Outcome $outcome)) {
        if ($failure -like '*already a member*') { continue }
        $result.Errors += ('{0} on {1}: {2}' -f $Method, $Name, $failure)
    }
    return $result
}
