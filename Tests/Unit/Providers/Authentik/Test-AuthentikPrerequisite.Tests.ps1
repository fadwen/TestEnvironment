#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The prerequisite check is what stops a seed from failing halfway, after some objects exist,
    because a data file was missing. The list of files it checks is typed by hand, so the one
    assertion that matters is that it names every CSV a seeding command actually reads: a step
    added with a new file and no entry here would pass the check and fail in the middle.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:ProviderRoot = Join-Path $script:ModuleRoot 'Providers\Authentik'
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Test-AuthentikPrerequisite' -Tag 'Unit', 'Private', 'Contract' {

    It 'checks every seed file a command reads, and no file that nothing reads' {
        $read = @(Get-ChildItem (Join-Path $script:ProviderRoot 'Public'), (Join-Path $script:ProviderRoot 'Private') -Filter *.ps1 |
                Select-String -Pattern "'(Authentik[A-Za-z]+\.csv)'" -AllMatches |
                ForEach-Object { $_.Matches | ForEach-Object { $_.Groups[1].Value } } |
                Sort-Object -Unique)
        $read.Count | Should-BeGreaterThan 10

        InModuleScope TestEnvironment -Parameters @{ read = $read } {
            param($read)
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com' } }
            Mock Get-AuthentikDataPath { $TestDrive }

            $ok = Test-AuthentikPrerequisite -CheckDataFiles -ErrorVariable problems -ErrorAction SilentlyContinue

            $ok | Should-BeFalse
            $checked = @($problems | ForEach-Object { [System.IO.Path]::GetFileName(($_.Exception.Message -replace '^Seed file missing: ', '')) } | Sort-Object -Unique)
            $checked | Should-BeCollection $read
        }
    }

    It 'passes when every file is present and fails when not connected' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com' } }
            Test-AuthentikPrerequisite -CheckDataFiles | Should-BeTrue

            Mock Get-AuthentikConnection { $null }
            Test-AuthentikPrerequisite -ErrorAction SilentlyContinue | Should-BeFalse
        }
    }
}
