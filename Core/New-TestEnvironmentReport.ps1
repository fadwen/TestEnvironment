function New-TestEnvironmentReport {
    <#
    .SYNOPSIS
        Builds the report object every provider's Get-<Provider>EnvironmentReport returns
    .DESCRIPTION
        One shape for six providers: Provider, Target and GeneratedOn first, then whatever the
        provider adds about itself, then Counts, Sections, and one property per section holding
        its rows. Sections is the ordered list of section names, and it is what the console
        renderer, the CSV writer and the HTML writer walk, so the three formats cannot drift
        from each other or from the object a script receives with -PassThru. Counts is one
        number per section in the same order.

        The report carries the shared type name TestEnvironmentReport and, in front of it, the
        provider's own, so a script can test for either.
    .PARAMETER Provider
        The provider the report came from, as Get-TestEnvironmentProvider names it
    .PARAMETER Target
        The tenant, domain, org, instance, realm or environment the report describes
    .PARAMETER Property
        Provider-specific facts about the estate as a whole - a prefix, a licence ceiling, a
        UPN suffix - in the order they should appear
    .PARAMETER Section
        The sections, in the order they are rendered: name to rows
    .PARAMETER TypeName
        The provider's own type name for the report, inserted ahead of the shared one
    .OUTPUTS
        PSCustomObject typed TestEnvironmentReport
    .EXAMPLE
        PS> New-TestEnvironmentReport -Provider Okta -Target $connection.OrgUrl -Property ([ordered]@{ Prefix = 'OKTALAB' }) -Section ([ordered]@{ Users = $users; Groups = $groups })

        A report with two sections, Counts of each, and Sections of ('Users', 'Groups').
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a report object in memory and changes nothing outside it.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Provider,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Target,

        [Parameter()]
        [System.Collections.IDictionary]$Property,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Section,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName
    )

    $report = [ordered]@{
        PSTypeName  = 'TestEnvironmentReport'
        Provider    = $Provider
        Target      = $Target
        GeneratedOn = Get-Date
    }
    if ($Property) {
        foreach ($entry in $Property.GetEnumerator()) { $report[[string]$entry.Key] = $entry.Value }
    }

    $counts = [ordered]@{}
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Section.GetEnumerator()) {
        $name = [string]$entry.Key
        $rows = @($entry.Value | Where-Object { $null -ne $_ })
        $report[$name] = $rows
        $counts[$name] = $rows.Count
        $names.Add($name)
    }
    $report['Counts'] = [PSCustomObject]$counts
    $report['Sections'] = $names.ToArray()

    $object = [PSCustomObject]$report
    if ($TypeName) { $object.PSObject.TypeNames.Insert(0, $TypeName) }
    return $object
}
