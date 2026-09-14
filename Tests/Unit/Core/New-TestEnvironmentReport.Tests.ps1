#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one report shape and the one file writer behind every provider's report. Pinned here
    once, so the per-provider report suites can be about their own sections: the shape carries
    Provider, Target, GeneratedOn, Counts, Sections and one property per section in the order
    given, with both type names; JSON is UTF-8 without a byte order mark and round-trips an
    accented name; CSV is one file per section, an empty file for an empty section, with lists
    joined rather than written as a type name; HTML has one heading per section with its count,
    encodes what it prints, and marks a warning so the one number a reader must not miss is not
    stated in the same voice as everything else.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'New-TestEnvironmentReport' -Tag 'Unit', 'Private' {

    It 'builds Provider, Target, GeneratedOn, the extra facts, Counts, Sections and one property per section, in order' {
        InModuleScope TestEnvironment {
            $report = New-TestEnvironmentReport -Provider 'Okta' -Target 'https://dev-1.okta.com' -TypeName 'OktaEnvironmentReport' `
                -Property ([ordered]@{ Prefix = 'OKTALAB'; Licence = [PSCustomObject]@{ Limit = 10 } }) `
                -Section ([ordered]@{ Users = @([PSCustomObject]@{ Login = 'a' }, [PSCustomObject]@{ Login = 'b' }); Groups = @(); Apps = @($null, [PSCustomObject]@{ Label = 'x' }) })

            @($report.PSObject.Properties.Name) | Should-BeCollection @('Provider', 'Target', 'GeneratedOn', 'Prefix', 'Licence', 'Users', 'Groups', 'Apps', 'Counts', 'Sections')
            $report.Provider | Should-Be 'Okta'
            $report.Target | Should-Be 'https://dev-1.okta.com'
            ($report.GeneratedOn -is [DateTime]) | Should-BeTrue
            $report.Prefix | Should-Be 'OKTALAB'
            $report.Licence.Limit | Should-Be 10
            @($report.Sections) | Should-BeCollection @('Users', 'Groups', 'Apps')
            $report.Counts.Users | Should-Be 2
            $report.Counts.Groups | Should-Be 0
            # A null row is dropped rather than counted.
            $report.Counts.Apps | Should-Be 1
            @($report.Groups) | Should-BeCollection -Count 0
            $report.PSObject.TypeNames[0] | Should-Be 'OktaEnvironmentReport'
            $report.PSObject.TypeNames[1] | Should-Be 'TestEnvironmentReport'
        }
    }
}

Describe 'Export-TestEnvironmentReport' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $accented = 'Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'
            $script:Accented = $accented
            $script:Report = New-TestEnvironmentReport -Provider 'Authentik' -Target 'https://auth.example.com' `
                -Property ([ordered]@{ Prefix = 'ZZ-TEST-' }) `
                -Section ([ordered]@{
                    Users  = @([PSCustomObject]@{ Username = 'zmueller'; Name = $accented; Groups = @('a', 'b'); Attributes = [PSCustomObject]@{ Clearance = 'Secret' } })
                    Groups = @()
                    Apps   = @([PSCustomObject]@{ Name = 'Tom & Jerry <Wiki>' })
                })
        }
    }

    It 'writes JSON as UTF-8 without a byte order mark, and it round-trips the accented name' {
        InModuleScope TestEnvironment {
            $path = Join-Path $TestDrive 'nested\report.json'
            Export-TestEnvironmentReport -Report $script:Report -OutputFormat JSON -OutputPath $path

            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should-BeFalse
            $parsed = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            $parsed.Provider | Should-Be 'Authentik'
            $parsed.Users[0].Name | Should-Be $script:Accented
            @($parsed.Sections) | Should-BeCollection @('Users', 'Groups', 'Apps')
        }
    }

    It 'writes one CSV per section with the prefix, an empty file for an empty section, lists joined and objects as JSON' {
        InModuleScope TestEnvironment {
            $folder = Join-Path $TestDrive 'csv'
            Export-TestEnvironmentReport -Report $script:Report -OutputFormat CSV -OutputPath $folder -FilePrefix 'AuthentikLab'

            @(Get-ChildItem -Path $folder -Filter *.csv).Name | Sort-Object | Should-BeCollection @('AuthentikLabApps.csv', 'AuthentikLabGroups.csv', 'AuthentikLabUsers.csv')
            (Get-Item (Join-Path $folder 'AuthentikLabGroups.csv')).Length | Should-Be 0
            $users = @(Import-Csv -Path (Join-Path $folder 'AuthentikLabUsers.csv') -Encoding UTF8)
            $users[0].Name | Should-Be $script:Accented
            $users[0].Groups | Should-Be 'a; b'
            $users[0].Attributes | Should-Be '{"Clearance":"Secret"}'
        }
    }

    It 'writes one HTML page with a heading and count per section, encodes what it prints, and marks a warning' {
        InModuleScope TestEnvironment {
            $path = Join-Path $TestDrive 'report.html'
            Export-TestEnvironmentReport -Report $script:Report -OutputFormat HTML -OutputPath $path -Title 'Authentik Lab' -Note 'A & B' -Warning 'Out of licences'

            $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            $html | Should-MatchString 'charset="utf-8"'
            $html | Should-MatchString '<title>Authentik Lab</title>'
            $html | Should-MatchString '<h1>Authentik Lab</h1>'
            $html | Should-MatchString 'Target https://auth.example.com'
            $html | Should-MatchString 'Prefix ZZ-TEST-'
            $html | Should-MatchString '<h2>Users \(1\)</h2>'
            $html | Should-MatchString '<h2>Groups \(0\)</h2>'
            $html | Should-MatchString '<h2>Apps \(1\)</h2>'
            $html | Should-MatchString '<p>A &amp; B</p>'
            $html | Should-MatchString '<p class="warn">Out of licences</p>'
            $html | Should-MatchString 'Tom &amp; Jerry &lt;Wiki&gt;'
            # ConvertTo-Html writes a non-ASCII character as a numeric entity, which is still the name.
            [System.Net.WebUtility]::HtmlDecode($html) | Should-MatchString ([regex]::Escape($script:Accented))
            $html | Should-NotMatchString 'System.Object'
        }
    }

    It 'defaults the title to the provider' {
        InModuleScope TestEnvironment {
            $path = Join-Path $TestDrive 'default.html'
            Export-TestEnvironmentReport -Report $script:Report -OutputFormat HTML -OutputPath $path
            [System.IO.File]::ReadAllText($path) | Should-MatchString '<h1>Authentik Test Environment Report</h1>'
        }
    }
}
