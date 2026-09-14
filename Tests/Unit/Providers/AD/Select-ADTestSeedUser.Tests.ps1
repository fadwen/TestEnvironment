#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    New-ADTestUser creates its users on background jobs, which a unit test cannot stand in
    for, so the two decisions it makes before any job starts are made in Select-ADTestSeedUser
    and tested here against the real data: which rows a tier keeps, that managers come before
    their reports, and that a manager left out by the tier is not looked for. The one thing
    the command itself is held to is that it asks the helper for the tier it was given.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
    $script:UsersCsv = Join-Path $moduleRoot 'Providers\AD\Data\ADUsers.csv'
    $script:SharedNames = @(Import-Csv -LiteralPath (Join-Path $moduleRoot 'Core\Data\SeedPeople.csv') -Encoding UTF8 | ForEach-Object { $_.DisplayName })
}

Describe 'Select-ADTestSeedUser' -Tag 'Unit', 'Private' {

    It 'keeps every row by default, managers first, and assigns every manager the data names' {
        InModuleScope TestEnvironment -Parameters @{ Path = $script:UsersCsv } {
            param($Path)
            $selection = Select-ADTestSeedUser -Path $Path

            @($selection.Users).Count | Should-Be 311
            # Every row with no manager comes before every row with one.
            $firstWithManager = [array]::FindIndex([object[]]@($selection.Users), [Predicate[object]]{ param($u) -not [string]::IsNullOrWhiteSpace($u.Manager) })
            @($selection.Users | Select-Object -First $firstWithManager | Where-Object { $_.Manager }).Count | Should-Be 0
            @($selection.ManagerAssignments).Count | Should-Be @($selection.Users | Where-Object { $_.Manager }).Count
        }
    }

    It 'keeps only the tier asked for, and both tiers when both are asked for' {
        InModuleScope TestEnvironment -Parameters @{ Path = $script:UsersCsv; Shared = $script:SharedNames } {
            param($Path, $Shared)
            $core = Select-ADTestSeedUser -Path $Path -Tier Core
            @($core.Users).Count | Should-Be 11
            @($core.Users | Where-Object { $_.Name -notin $Shared }).Count | Should-Be 0

            @((Select-ADTestSeedUser -Path $Path -Tier Bulk).Users).Count | Should-Be 300
            @((Select-ADTestSeedUser -Path $Path -Tier Core, Bulk).Users).Count | Should-Be 311
        }
    }

    It 'assigns a manager only when the manager is among the rows being created, and says so about the rest' {
        InModuleScope TestEnvironment -Parameters @{ Path = $script:UsersCsv } {
            param($Path)
            $core = Select-ADTestSeedUser -Path $Path -Tier Core -Verbose 4>&1
            $verbose = @($core | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $selection = @($core | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]

            $coreNames = @($selection.Users | ForEach-Object { $_.Name })
            $withManager = @($selection.Users | Where-Object { $_.Manager })
            $expected = @($withManager | Where-Object { ($_.Manager -replace '^CN=', '') -in $coreNames })
            @($selection.ManagerAssignments).Count | Should-Be $expected.Count
            @($selection.ManagerAssignments | Where-Object { ($_.Manager -replace '^CN=', '') -notin $coreNames }).Count | Should-Be 0

            # The people whose manager was left out are named, one line each, and not errors.
            $leftOut = $withManager.Count - $expected.Count
            $leftOut | Should-BeGreaterThan 0
            @($verbose | Where-Object { "$_" -like 'Not setting the manager of *is not among the users being created' }).Count | Should-Be $leftOut
        }
    }
}

Describe 'New-ADTestUser' -Tag 'Unit', 'Public' {

    It 'asks for the tier it was given before any job starts' {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Get-ADTestDomain { @{ DNSName = 'lab.local'; DomainDN = 'DC=lab,DC=local'; ForestDN = 'DC=lab,DC=local' } }
            Mock Select-ADTestSeedUser { [PSCustomObject]@{ Users = @(); ManagerAssignments = @() } }
            Mock Start-Job { throw 'a job escaped the mocks' }

            $null = New-ADTestUser -Tier Core -Confirm:$false 6>$null

            Should-Invoke Select-ADTestSeedUser -Times 1 -Exactly -ParameterFilter { @($Tier) -eq 'Core' -and $Path -like '*ADUsers.csv' }
            Should-NotInvoke Start-Job
        }
    }
}
