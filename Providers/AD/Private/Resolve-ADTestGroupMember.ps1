function Resolve-ADTestGroupMember {
    <#
    .SYNOPSIS
        Resolves the members a seeded group's rule names, inside the seed OU only

    .DESCRIPTION
        A row in ADSecurityGroups.csv with AutoAssignment set carries its membership rule in
        three columns, and this is the one place they are interpreted:

        - MemberFilter  an Active Directory filter, as Get-ADUser -Filter takes it, over the
                        users in the seed OU: "Department -eq 'Sales' -and Title -like '*Manager*'".
        - MemberSource  blank or User for the users the filter matches; DeviceOwner to run the
                        filter over the seeded computers instead and return their managedBy owners.
        - MemberLimit   a number, to take only the first so many, ordered by account name so the
                        same people are chosen on every run.

        Every search is scoped to the seed's root OU. The rules once lived as a regex switch in
        the group step, searching the whole domain, and a rule such as "every enabled account"
        took in every enabled account the domain held: a live run put twelve real accounts,
        Administrator among them, into seeded groups. A device owner is looked up by identity,
        which cannot take a search base, so the owner's distinguished name is checked instead.

        The result is unique by distinguished name. A rule that matches the same person twice
        used to count that person as two members added.

    .PARAMETER Rule
        The CSV row: GroupName, MemberFilter, MemberSource and MemberLimit are read.

    .PARAMETER SeedRoot
        The distinguished name of the seed's root OU.

    .OUTPUTS
        Microsoft.ActiveDirectory.Management.ADUser, or nothing when the rule matches nobody.

    .EXAMPLE
        PS> Resolve-ADTestGroupMember -Rule $row -SeedRoot 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'

        DESCRIPTION: Resolves one group's members
        OUTPUT: The users the row's rule names, each once
        USE CASE: Called by New-ADTestSecurityGroups for every row with AutoAssignment set

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Rule,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SeedRoot
    )

    $filter = [string]$Rule.MemberFilter
    if ([string]::IsNullOrWhiteSpace($filter)) {
        Write-Verbose "No membership rule for $($Rule.GroupName); the group is left empty"
        return
    }

    $source = if ($Rule.PSObject.Properties['MemberSource'] -and $Rule.MemberSource) { [string]$Rule.MemberSource } else { 'User' }

    $members = switch ($source) {
        'DeviceOwner' {
            # The filter picks computers; the members are the people those computers are
            # managed by. -Identity cannot be combined with -SearchBase, so an owner outside
            # the seed OU is dropped by its distinguished name instead.
            $owners = @(Get-ADComputer -Filter $filter -SearchBase $SeedRoot -Properties ManagedBy -ErrorAction Stop |
                    Where-Object { $_.ManagedBy } | ForEach-Object { $_.ManagedBy } | Sort-Object -Unique)
            foreach ($owner in $owners) {
                if ($owner -notlike "*,$SeedRoot") { continue }
                Get-ADUser -Identity $owner -ErrorAction SilentlyContinue
            }
        }
        'User' {
            Get-ADUser -Filter $filter -SearchBase $SeedRoot -ErrorAction Stop
        }
        default {
            throw "Group '$($Rule.GroupName)' names an unknown MemberSource '$source'. Use User or DeviceOwner."
        }
    }

    $members = @($members | Where-Object { $_ -and $_.DistinguishedName } | Sort-Object -Property DistinguishedName -Unique)

    if ($Rule.PSObject.Properties['MemberLimit'] -and -not [string]::IsNullOrWhiteSpace([string]$Rule.MemberLimit)) {
        $limit = [int]$Rule.MemberLimit
        # Ordered by account name first, so the limit picks the same people on every run rather
        # than whichever the directory happened to return first.
        $members = @($members | Sort-Object -Property SamAccountName | Select-Object -First $limit)
    }

    $members
}
