#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The Active Directory report had three file writers of its own, fifteen hundred lines that
    exported whole ADUser objects and named their files differently from every other provider.
    It now projects each object to the columns a reader wants, returns the one report shape, and
    writes its files through the one writer. These pin the shape and the files, that every search
    stays under the seed OU, that the report reads only the properties it shows, and that a file
    format with no path is refused rather than defaulted to a timestamped name in the current
    directory.

    Everything is mocked. The directory is never reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-ADEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
            $root = 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
            Mock Get-ADOrganizationalUnit { @([PSCustomObject]@{ Name = 'Users'; DistinguishedName = "OU=Users,$root"; Description = 'x'; ProtectedFromAccidentalDeletion = $true }) }
            Mock Get-ADUser {
                if ($SearchBase -like 'OU=Users,*') {
                    return @([PSCustomObject]@{ Name = ('Jos' + [string][char]0xE9 + ' Ni' + [string][char]0xF1 + 'o'); SamAccountName = 'josen'; UserPrincipalName = 'josen@contoso.com'; DisplayName = 'x'; Department = 'Engineering'; Title = 'Engineer'; Office = 'SEA'; Enabled = $true; Manager = $null; Description = ''; DistinguishedName = "CN=x,OU=Engineering,OU=Users,$root"; ObjectGUID = 'guid'; SID = 'S-1' })
                }
                @([PSCustomObject]@{ Name = 'SQL Service'; SamAccountName = 'svc-sql'; Description = 'y'; Enabled = $true; ServicePrincipalNames = @('MSSQLSvc/a', 'MSSQLSvc/b'); TrustedForDelegation = $false; DistinguishedName = "CN=SQL Service,OU=ServiceAccounts,$root" })
            }
            Mock Get-ADComputer { @([PSCustomObject]@{ Name = 'ZZ-TEST-SEA-ENG-001'; OperatingSystem = 'Windows 11'; OperatingSystemVersion = '10.0'; Enabled = $true; Description = ''; DistinguishedName = "CN=ZZ-TEST-SEA-ENG-001,OU=Devices,$root" }) }
            Mock Get-ADGroup { @([PSCustomObject]@{ Name = 'ZZ-TEST-Engineering'; GroupScope = 'Global'; GroupCategory = 'Security'; Description = 'z'; DistinguishedName = "CN=ZZ-TEST-Engineering,OU=Groups,$root" }) }
            Mock Get-ADGroupMember { @([PSCustomObject]@{ Name = 'x'; objectClass = 'user'; DistinguishedName = "CN=x,OU=Engineering,OU=Users,$root"; SamAccountName = 'josen' }) }
        }
    }

    It 'returns the shared report shape with -PassThru, projected to the columns it shows, reading only those properties under the seed OU' {
        InModuleScope TestEnvironment {
            $report = Get-ADEnvironmentReport -PassThru

            $report.PSObject.TypeNames[0] | Should-Be 'ADEnvironmentReport'
            $report.PSObject.TypeNames[1] | Should-Be 'TestEnvironmentReport'
            $report.Provider | Should-Be 'AD'
            $report.Target | Should-Be 'contoso.com'
            @($report.Sections) | Should-BeCollection @('OrganizationalUnits', 'Users', 'ServiceAccounts', 'Devices', 'Groups', 'GroupMembers')
            $report.Counts.Users | Should-Be 1
            $report.Counts.GroupMembers | Should-Be 1
            $report.Groups[0].MemberCount | Should-Be 1
            @($report.Users[0].PSObject.Properties.Name) | Should-NotContainCollection @('ObjectGUID', 'SID')
            @($report.ServiceAccounts[0].ServicePrincipalNames).Count | Should-Be 2

            Should-Invoke Get-ADUser -Times 2 -Exactly -ParameterFilter { $SearchBase -like '*OU=ZZ-TEST-TestData,DC=contoso,DC=com' -and @($Properties) -notcontains '*' }
            Should-Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Devices,OU=ZZ-TEST-TestData,DC=contoso,DC=com' -and @($Properties) -notcontains '*' }
            Should-Invoke Get-ADGroup -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com' -and @($Properties) -notcontains '*' }
        }
    }

    It 'writes every file format as UTF-8 through the shared writer, requires a path for one, and puts nothing on the pipeline without -PassThru' {
        InModuleScope TestEnvironment {
            { Get-ADEnvironmentReport -OutputFormat JSON } | Should-Throw -ExceptionMessage '*-OutputPath*'
            (Get-ADEnvironmentReport) | Should-BeNull

            $jose = 'Jos' + [string][char]0xE9
            $json = Join-Path $TestDrive 'r.json'
            Get-ADEnvironmentReport -OutputFormat JSON -OutputPath $json
            [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | Should-MatchString ([regex]::Escape($jose))

            $folder = Join-Path $TestDrive 'csv'
            Get-ADEnvironmentReport -OutputFormat CSV -OutputPath $folder
            @(Get-ChildItem $folder -Filter 'ADLab*.csv').Name | Sort-Object | Should-BeCollection @('ADLabDevices.csv', 'ADLabGroupMembers.csv', 'ADLabGroups.csv', 'ADLabOrganizationalUnits.csv', 'ADLabServiceAccounts.csv', 'ADLabUsers.csv')
            (Import-Csv (Join-Path $folder 'ADLabServiceAccounts.csv') -Encoding UTF8)[0].ServicePrincipalNames | Should-Be 'MSSQLSvc/a; MSSQLSvc/b'

            $html = Join-Path $TestDrive 'r.html'
            Get-ADEnvironmentReport -OutputFormat HTML -OutputPath $html
            $page = [System.IO.File]::ReadAllText($html, [System.Text.Encoding]::UTF8)
            $page | Should-MatchString '<h2>Users \(1\)</h2>'
            $page | Should-MatchString 'Domain contoso.com'
        }
    }
}
