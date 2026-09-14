#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The PingOne report was console and -PassThru only, while every other provider also wrote
    JSON, CSV and HTML. It now takes the shared -OutputFormat, -OutputPath and -PassThru, returns
    the one report shape with a section for every object type the provider owns, and writes its
    files through the one writer. These pin that, and that a report reaches the pipeline only
    with -PassThru.

    Everything is mocked. The environment is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-PingOneEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Get-PingOneConnection { @{ EnvironmentId = 'env-1'; EnvironmentName = 'Ping-Test'; Prefix = 'ZZ-TEST-' } }
            $script:Fixture = @{
                Attributes   = @([PSCustomObject]@{ id = 'at1'; name = 'zzTestSeedTag'; type = 'STRING'; required = $false; unique = $false })
                Populations  = @([PSCustomObject]@{ id = 'p1'; name = 'ZZ-TEST-Employees'; description = 'x' }, [PSCustomObject]@{ id = 'p2'; name = 'ZZ-TEST-Empty'; description = 'y' })
                Users        = @(
                    [PSCustomObject]@{ id = 'u1'; username = 'zz-test-jnino'; name = [PSCustomObject]@{ given = ('Jos' + [string][char]0xE9); family = ('Ni' + [string][char]0xF1 + 'o') }; population = [PSCustomObject]@{ id = 'p1' }; enabled = $true; mfaEnabled = $true }
                    [PSCustomObject]@{ id = 'u2'; username = 'zz-test-mbell'; name = [PSCustomObject]@{ given = 'Marcus'; family = 'Bell' }; population = [PSCustomObject]@{ id = 'p1' }; enabled = $false; mfaEnabled = $false }
                )
                Groups       = @([PSCustomObject]@{ id = 'g1'; name = 'ZZ-TEST-Engineering'; directMemberCounts = [PSCustomObject]@{ users = 2; groups = 0 } })
                Resources    = @([PSCustomObject]@{ id = 'r1'; name = 'ZZ-TEST-Payroll API'; audience = 'payroll'; type = 'CUSTOM' })
                Applications = @([PSCustomObject]@{ id = 'a1'; name = 'ZZ-TEST-Portal'; protocol = 'OPENID_CONNECT'; type = 'WEB_APP'; enabled = $true })
            }
            Mock Get-PingOneSeededObject { @($script:Fixture[$Type]) }
            Mock Invoke-PingOneRequest { throw "Unexpected request $Method $Path" }
        }
    }

    It 'returns the shared report shape with -PassThru, a section per object type, and nothing without it' {
        InModuleScope TestEnvironment {
            (Get-PingOneEnvironmentReport) | Should-BeNull

            $report = Get-PingOneEnvironmentReport -PassThru
            $report.PSObject.TypeNames[0] | Should-Be 'PingOneEnvironmentReport'
            $report.PSObject.TypeNames[1] | Should-Be 'TestEnvironmentReport'
            $report.Provider | Should-Be 'PingOne'
            $report.Target | Should-Be 'env-1'
            @($report.Sections) | Should-BeCollection @('Attributes', 'Populations', 'Users', 'Groups', 'Resources', 'Applications')
            $report.Counts.Users | Should-Be 2
            $report.Counts.Populations | Should-Be 2
            $report.UsersDisabled | Should-Be 1
            $report.UsersWithMfa | Should-Be 1
            $report.UsersByPopulation.'ZZ-TEST-Employees' | Should-Be 2
            ($report.Populations | Where-Object Name -eq 'ZZ-TEST-Employees').Users | Should-Be 2
            ($report.Users | Where-Object Username -eq 'zz-test-jnino').Population | Should-Be 'ZZ-TEST-Employees'
            $report.Groups[0].Kind | Should-Be 'Static'
        }
    }

    It 'writes every file format as UTF-8 through the shared writer and requires a path for one' {
        InModuleScope TestEnvironment {
            { Get-PingOneEnvironmentReport -OutputFormat CSV } | Should-Throw -ExceptionMessage '*-OutputPath*'

            $jose = 'Jos' + [string][char]0xE9
            $json = Join-Path $TestDrive 'r.json'
            Get-PingOneEnvironmentReport -OutputFormat JSON -OutputPath $json
            [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | Should-MatchString ([regex]::Escape($jose))

            $folder = Join-Path $TestDrive 'csv'
            Get-PingOneEnvironmentReport -OutputFormat CSV -OutputPath $folder
            @(Get-ChildItem $folder -Filter 'PingOneLab*.csv').Count | Should-Be 6
            (Import-Csv (Join-Path $folder 'PingOneLabUsers.csv') -Encoding UTF8 | Where-Object Username -eq 'zz-test-jnino').GivenName | Should-Be $jose

            $html = Join-Path $TestDrive 'r.html'
            Get-PingOneEnvironmentReport -OutputFormat HTML -OutputPath $html
            $page = [System.IO.File]::ReadAllText($html, [System.Text.Encoding]::UTF8)
            $page | Should-MatchString '<h2>Populations \(2\)</h2>'
            $page | Should-MatchString 'Environment Ping-Test \(env-1\)'
        }
    }
}
