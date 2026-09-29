function Get-OneLoginSeedScope {
    <#
    .SYNOPSIS
        Returns the roles and groups the seeded people of the chosen tiers will hold

    .DESCRIPTION
        A seeded role or group has nothing but its name to say who made it, so teardown proves it
        by what it holds: every member a seeded person, and at least one of them. An empty role
        cannot be proved, and teardown leaves it alone - which is right for somebody else's empty
        role and wrong for one this module made and then never filled.

        So the seed never makes a role or group that none of the people it is about to seed will
        hold. With every tier that is all of them, because the data gives every role and group a
        Core member and a test holds it to that. With -Tier Bulk alone it is fewer: Finance,
        Leadership and Partners have only Core members, and seeding them empty would leave three
        objects behind that no teardown could claim.

        The roles, groups, apps and mappings steps all ask this, so the four agree about which
        roles exist without passing anything between them.

    .PARAMETER Tier
        The tiers of people being seeded. Both when omitted.

    .OUTPUTS
        PSCustomObject with Roles and Groups, each a set of row keys.

    .EXAMPLE
        PS> (Get-OneLoginSeedScope -Tier Bulk).Roles.Contains('finance')

        DESCRIPTION: Asks whether a Bulk-only seed would give Finance a member
        OUTPUT: False
        USE CASE: New-OneLoginRole skipping a role nobody in the tier holds

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Core', 'Bulk')]
        [string[]]$Tier
    )

    $rows = @(Import-Csv -LiteralPath (Join-Path (Get-OneLoginDataPath) 'OneLoginUsers.csv') -Encoding UTF8)
    if ($Tier) { $rows = @($rows | Where-Object { $Tier -contains $_.Tier }) }

    $roles = New-Object 'System.Collections.Generic.HashSet[string]'
    $groups = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($row in $rows) {
        foreach ($role in @(([string]$row.Roles -split ';') | Where-Object { $_ })) { $null = $roles.Add($role) }
        if ($row.Group) { $null = $groups.Add([string]$row.Group) }
    }

    return [PSCustomObject]@{
        Roles  = $roles
        Groups = $groups
    }
}
