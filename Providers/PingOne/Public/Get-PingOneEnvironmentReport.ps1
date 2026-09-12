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

    .PARAMETER PassThru
        Return the report object instead of writing a summary.

    .OUTPUTS
        PSCustomObject, the report.

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
        [switch]$PassThru
    )

    $connection = Get-PingOneConnection

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

    $report = [PSCustomObject]@{
        EnvironmentId     = $connection.EnvironmentId
        EnvironmentName   = $connection.EnvironmentName
        Prefix            = $connection.Prefix
        GeneratedAt       = Get-Date
        Counts            = [PSCustomObject][ordered]@{
            Attributes   = $attributes.Count
            Populations  = $populations.Count
            Users        = $users.Count
            Groups       = $groups.Count
            Resources    = $resources.Count
            Applications = $applications.Count
        }
        UsersByPopulation = [PSCustomObject]$usersByPopulation
        UsersDisabled     = @($users | Where-Object { -not $_.enabled }).Count
        UsersWithMfa      = @($users | Where-Object { $_.mfaEnabled }).Count
        Groups            = @($groupRows)
        Applications      = @($applicationRows)
    }

    if ($PassThru) { return $report }

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
