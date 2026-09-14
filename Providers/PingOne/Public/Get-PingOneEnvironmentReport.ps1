function Get-PingOneEnvironmentReport {
    <#
    .SYNOPSIS
        Reports what this module has seeded in a PingOne environment, and what shape it is in

    .DESCRIPTION
        Reached through Get-TestEnvironmentReport once a PingOne connection is active.

        Only objects this module can prove it created are counted, using the same selection
        teardown uses, so the report and the teardown can never disagree about what is ours.

        Beyond counts, it surfaces the states the seed exists to create, because a report that
        says "330 users" and nothing else proves nothing about whether a script handles a
        disabled user who still holds memberships:

        - Users by population, enabled, and MFA state.
        - Groups by kind: static, dynamic, and scoped to a population, with direct member
          counts. A dynamic group's count is PingOne's own and lags behind reality until the
          filter evaluates, so a dynamic group reporting zero immediately after a seed is
          expected rather than broken.
        - Applications by protocol and type, with how many are enabled.

        Read-only. Nothing in the environment changes.

        Console output is for a person; JSON, CSV and HTML are for a file, written by the one
        writer every provider shares, as UTF-8. The report object is the shape every provider
        returns: Provider, Target, GeneratedOn, the environment's own facts, Counts, Sections,
        and one property per section.
    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console.

    .PARAMETER PassThru
        Returns the report object as well.

    .OUTPUTS
        PingOneEnvironmentReport, when -PassThru is supplied.

    .EXAMPLE
        PS> Get-TestEnvironmentReport

        DESCRIPTION: Summarises the seeded environment
        OUTPUT: Counts and state breakdowns per object type
        USE CASE: Confirming a seed produced what it should

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-PingOneEnvironment
        Remove-PingOneEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The summary is written for a person reading it; -PassThru returns the object for scripts.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection
    if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $attributes = @(Get-PingOneSeededObject -Type Attributes -Connection $connection)
    $populations = @(Get-PingOneSeededObject -Type Populations -Connection $connection)
    $users = @(Get-PingOneSeededObject -Type Users -Connection $connection)
    $groups = @(Get-PingOneSeededObject -Type Groups -Connection $connection)
    $resources = @(Get-PingOneSeededObject -Type Resources -Connection $connection)
    $applications = @(Get-PingOneSeededObject -Type Applications -Connection $connection)

    $populationName = @{}
    foreach ($population in $populations) { $populationName[[string]$population.id] = $population.name }

    $usersByPopulation = [ordered]@{}
    foreach ($group in ($users | Group-Object { $populationName[[string]$_.population.id] } | Sort-Object Name)) {
        $label = if ($group.Name) { $group.Name } else { '(not in a seeded population)' }
        $usersByPopulation[$label] = $group.Count
    }

    $groupRows = foreach ($group in ($groups | Sort-Object name)) {
        $kind = if ($group.userFilter) { 'Dynamic' } elseif ($group.population) { 'Population-scoped' } else { 'Static' }
        [PSCustomObject]@{
            Name          = $group.name
            Kind          = $kind
            DirectUsers   = [int]$group.directMemberCounts.users
            DirectGroups  = [int]$group.directMemberCounts.groups
        }
    }

    $applicationRows = foreach ($application in ($applications | Sort-Object name)) {
        [PSCustomObject]@{
            Name     = $application.name
            Protocol = $application.protocol
            Type     = $application.type
            Enabled  = [bool]$application.enabled
        }
    }

    $populationRows = foreach ($population in ($populations | Sort-Object name)) {
        [PSCustomObject]@{
            Name        = $population.name
            Description = $population.description
            Users       = @($users | Where-Object { [string]$_.population.id -eq [string]$population.id }).Count
        }
    }
    $userRows = foreach ($user in ($users | Sort-Object username)) {
        [PSCustomObject]@{
            Username   = $user.username
            GivenName  = $user.name.given
            FamilyName = $user.name.family
            Population = $populationName[[string]$user.population.id]
            Enabled    = [bool]$user.enabled
            MfaEnabled = [bool]$user.mfaEnabled
        }
    }
    $resourceRows = foreach ($resource in ($resources | Sort-Object name)) {
        [PSCustomObject]@{ Name = $resource.name; Audience = $resource.audience; Type = $resource.type }
    }
    $attributeRows = foreach ($attribute in ($attributes | Sort-Object name)) {
        [PSCustomObject]@{ Name = $attribute.name; Type = $attribute.type; Required = [bool]$attribute.required; Unique = [bool]$attribute.unique }
    }

    $report = New-TestEnvironmentReport -Provider 'PingOne' -Target $connection.EnvironmentId -TypeName 'PingOneEnvironmentReport' `
        -Property ([ordered]@{
            EnvironmentId     = $connection.EnvironmentId
            EnvironmentName   = $connection.EnvironmentName
            Prefix            = $connection.Prefix
            UsersByPopulation = [PSCustomObject]$usersByPopulation
            UsersDisabled     = @($users | Where-Object { -not $_.enabled }).Count
            UsersWithMfa      = @($users | Where-Object { $_.mfaEnabled }).Count
        }) `
        -Section ([ordered]@{
            Attributes   = @($attributeRows)
            Populations  = @($populationRows)
            Users        = @($userRows)
            Groups       = @($groupRows)
            Resources    = @($resourceRows)
            Applications = @($applicationRows)
        })

    if ($OutputFormat -eq 'Console') {
        Write-TestMessage -Message ("PingOne Test Environment Report ({0})" -f $connection.EnvironmentName) -Type Header
        Write-Host 'Counts'
        foreach ($property in $report.Counts.PSObject.Properties) {
            Write-Host ("  {0,-14} {1}" -f $property.Name, $property.Value)
        }
        Write-Host ''
        Write-Host 'Users by population'
        foreach ($property in $report.UsersByPopulation.PSObject.Properties) {
            Write-Host ("  {0,-32} {1}" -f $property.Name, $property.Value)
        }
        Write-Host ("  disabled {0}, with MFA {1}" -f $report.UsersDisabled, $report.UsersWithMfa)
        Write-Host ''
        Write-Host 'Groups'
        $report.Groups | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
        Write-Host 'Applications'
        $report.Applications | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
    }
    else {
        Export-TestEnvironmentReport -Report $report -OutputFormat $OutputFormat -OutputPath $OutputPath `
            -FilePrefix 'PingOneLab' -Title 'PingOne Test Environment Report' `
            -Note @("Environment $($connection.EnvironmentName) ($($connection.EnvironmentId))")
    }

    if ($PassThru) { return $report }
}
