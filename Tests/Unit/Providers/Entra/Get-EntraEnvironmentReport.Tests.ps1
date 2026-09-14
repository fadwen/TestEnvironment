#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The Entra report had parameters of its own - -Format with an Object value, -Path with a
    default - while every other provider took -OutputFormat, -OutputPath and -PassThru, and the
    dispatcher's help had to explain both. It now takes the shared three, keeps the old names as
    aliases so a script written against them still binds, returns the one report shape, and
    writes its files through the one writer. These pin that, and that an unreadable role
    eligibility read is reported as unknown rather than as zero.

    Everything is mocked. The tenant is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-EntraEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Get-EntraConnection { @{ TenantId = 'tenant-1'; TenantName = 'Contoso Lab'; UpnSuffix = 'lab.example.com' } }
            Mock Get-EntraSeedMarker { [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; Tag = 'ZZ-TEST-seed'; UpnSuffix = 'lab.example.com' } }
            $script:Fixture = @{
                Users             = @(
                    [PSCustomObject]@{ id = 'u1'; displayName = ('Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'); userPrincipalName = 'ZZ-TEST-zmueller@lab.example.com'; accountEnabled = $true; userType = 'Member'; department = 'Engineering' }
                    [PSCustomObject]@{ id = 'u2'; displayName = 'Guest One'; userPrincipalName = 'guest_example.com#EXT#@lab.example.com'; accountEnabled = $true; userType = 'Guest'; externalUserState = 'PendingAcceptance' }
                )
                Groups            = @([PSCustomObject]@{ id = 'g1'; displayName = 'ZZ-TEST-Engineering'; groupTypes = @(); assignedLicenses = @() })
                Devices           = @([PSCustomObject]@{ id = 'd1'; displayName = 'ZZ-TEST-SEA-ENG-001'; operatingSystem = 'Windows' })
                Applications      = @([PSCustomObject]@{ id = 'a1'; appId = 'app-1'; displayName = 'ZZ-TEST-Portal'; tags = @() })
                ServicePrincipals = @([PSCustomObject]@{ id = 'sp1'; appId = 'app-1'; displayName = 'ZZ-TEST-Portal' })
                DirectoryRoles    = @()
            }
            Mock Get-EntraSeededObject {
                if ($Type -eq 'RoleEligibilities') { throw 'AadPremiumLicenseRequired' }
                if ($script:Fixture.ContainsKey($Type)) { return @($script:Fixture[$Type]) }
                @()
            }
            Mock Invoke-EntraBatch {
                foreach ($item in @($Request)) {
                    $body = if ($item.Url -like '*/manager*') { [PSCustomObject]@{ displayName = 'Ada Whitfield' } }
                    elseif ($item.Url -like '*licenseAssignmentStates*') { [PSCustomObject]@{ licenseAssignmentStates = @() } }
                    else { 3 }
                    [PSCustomObject]@{ Reference = $item.Reference; Success = $true; Status = 200; Body = $body }
                }
            }
            Mock Invoke-EntraRequest {
                if ($Path -eq '/subscribedSkus') { return [PSCustomObject]@{ value = @() } }
                @()
            }
        }
    }

    It 'returns the shared report shape with -PassThru, and reports an unreadable eligibility count as unknown' {
        InModuleScope TestEnvironment {
            $report = Get-EntraEnvironmentReport -PassThru -WarningAction SilentlyContinue

            $report.PSObject.TypeNames[0] | Should-Be 'EntraEnvironmentReport'
            $report.PSObject.TypeNames[1] | Should-Be 'TestEnvironmentReport'
            $report.Provider | Should-Be 'Entra'
            $report.Target | Should-Be 'tenant-1'
            @($report.Sections) | Should-BeCollection @('Users', 'Groups', 'Applications', 'Devices', 'NamedLocations', 'Policies', 'RoleEligibilities')
            $report.Counts.Users | Should-Be 2
            $report.Counts.Groups | Should-Be 1
            $report.GuestsByUserType | Should-Be 1
            $report.GuestsPendingAcceptance | Should-Be 1
            $report.ServicePrincipals | Should-Be 1
            $report.RoleEligibilityCount | Should-BeNull
            $report.Groups[0].DirectMembers | Should-Be 3
            $report.Users[0].Manager | Should-Be 'Ada Whitfield'
        }
    }

    It 'still binds the names it had before the surface was unified' {
        InModuleScope TestEnvironment {
            $path = Join-Path $TestDrive 'alias.json'
            $null = Get-EntraEnvironmentReport -Format JSON -Path $path -WarningAction SilentlyContinue
            Test-Path -LiteralPath $path | Should-BeTrue
            { Get-EntraEnvironmentReport -Format Object } | Should-Throw
        }
    }

    It 'writes every file format as UTF-8 through the shared writer, requires a path for one, and puts nothing on the pipeline without -PassThru' {
        InModuleScope TestEnvironment {
            { Get-EntraEnvironmentReport -OutputFormat JSON } | Should-Throw -ExceptionMessage '*-OutputPath*'

            $accented = 'Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'
            $json = Join-Path $TestDrive 'r.json'
            $out = Get-EntraEnvironmentReport -OutputFormat JSON -OutputPath $json -WarningAction SilentlyContinue
            $out | Should-BeNull
            [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | Should-MatchString ([regex]::Escape($accented))

            $folder = Join-Path $TestDrive 'csv'
            Get-EntraEnvironmentReport -OutputFormat CSV -OutputPath $folder -WarningAction SilentlyContinue
            @(Get-ChildItem $folder -Filter 'EntraLab*.csv').Count | Should-Be 7
            (Import-Csv (Join-Path $folder 'EntraLabUsers.csv') -Encoding UTF8)[0].DisplayName | Should-Be $accented

            $html = Join-Path $TestDrive 'r.html'
            Get-EntraEnvironmentReport -OutputFormat HTML -OutputPath $html -WarningAction SilentlyContinue
            $page = [System.IO.File]::ReadAllText($html, [System.Text.Encoding]::UTF8)
            $page | Should-MatchString '<h2>Users \(2\)</h2>'
            $page | Should-MatchString 'Tenant Contoso Lab \(tenant-1\)'
        }
    }
}
