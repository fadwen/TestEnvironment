#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The small helpers every step leans on. The seed marker is where one prefix becomes the
    lower-case name FreeIPA accepts and the tag its userclass carries, and a step that spelled
    either differently would seed objects teardown cannot find. The name resolver is the one
    place a seed key becomes a realm name, including the builtin: escape that lets a row name
    a stock object without the seed ever creating one. The date helpers read the
    {"__datetime__"} shape FreeIPA answers with and write the generalized time it accepts.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreeIPASeedMarker and Get-FreeIPAServiceAccountName' -Tag 'Unit', 'Private' {

    It 'derives the lower-case name prefix, the tag, the marker and the class attribute from one prefix' {
        InModuleScope TestEnvironment {
            $marker = Get-FreeIPASeedMarker -Connection @{ Prefix = 'ZZ-TEST-' }
            $marker.Prefix | Should-Be 'ZZ-TEST-'
            $marker.NamePrefix | Should-Be 'zz-test-'
            $marker.Tag | Should-Be 'ZZ-TEST-seed'
            $marker.Marker | Should-Be '[ZZ-TEST-seed]'
            $marker.Attribute | Should-Be 'userclass'
            Get-FreeIPAServiceAccountName -Marker $marker | Should-Be 'zz-test-automation'
        }
    }

    It 'follows a non-default prefix everywhere' {
        InModuleScope TestEnvironment {
            $marker = Get-FreeIPASeedMarker -Connection @{ Prefix = 'LAB_' }
            $marker.NamePrefix | Should-Be 'lab_'
            $marker.Tag | Should-Be 'LAB_seed'
            Get-FreeIPAServiceAccountName -Marker $marker | Should-Be 'lab_automation'
        }
    }
}

Describe 'Resolve-FreeIPASeedName' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:FreeIPAConnection = @{ Prefix = 'ZZ-TEST-'; Domain = 'ipa.example.com' }
        }
    }

    It 'prefixes a key, qualifies a host with the realm domain, and passes a command path through' {
        InModuleScope TestEnvironment {
            Resolve-FreeIPASeedName -Key 'All-Staff' | Should-Be 'zz-test-all-staff'
            Resolve-FreeIPASeedName -Key 'web01' -Kind Host | Should-Be 'zz-test-web01.zz-test-lab.ipa.example.com'
            Resolve-FreeIPASeedName -Key '/usr/bin/vim' -Kind Command | Should-Be '/usr/bin/vim'
            Resolve-FreeIPASeedName -Key '/usr/bin/vim' | Should-Be '/usr/bin/vim'
            Resolve-FreeIPASeedName -Key '' | Should-Be ''
        }
    }

    It 'returns a stock object''s own name for a builtin: reference, never prefixed' {
        InModuleScope TestEnvironment {
            Resolve-FreeIPASeedName -Key 'builtin:sshd' | Should-Be 'sshd'
            Resolve-FreeIPASeedName -Key 'builtin:Password Policy Readers' | Should-Be 'Password Policy Readers'
        }
    }

    It 'refuses to qualify a host when the connection has no domain' {
        InModuleScope TestEnvironment {
            { Resolve-FreeIPASeedName -Key 'web01' -Kind Host -Connection @{ Prefix = 'ZZ-TEST-'; Domain = '' } } | Should-Throw -ExceptionMessage '*no domain*'
        }
    }
}

Describe 'ConvertFrom-FreeIPADateTime and ConvertTo-FreeIPADateTime' -Tag 'Unit', 'Private' {

    It 'reads the object, the bare string and a list of one, all as UTC' {
        InModuleScope TestEnvironment {
            $expected = [DateTimeOffset]::new(2026, 12, 10, 2, 47, 34, [TimeSpan]::Zero)
            (ConvertFrom-FreeIPADateTime -Value ([PSCustomObject]@{ __datetime__ = '20261210024734Z' })) | Should-Be $expected
            (ConvertFrom-FreeIPADateTime -Value '20261210024734Z') | Should-Be $expected
            (ConvertFrom-FreeIPADateTime -Value @([PSCustomObject]@{ __datetime__ = '20261210024734Z' })) | Should-Be $expected
            (ConvertFrom-FreeIPADateTime -Value $null) | Should-BeNull
            (ConvertFrom-FreeIPADateTime -Value @()) | Should-BeNull
            (ConvertFrom-FreeIPADateTime -Value 'not a date') | Should-BeNull
        }
    }

    It 'writes generalized time in UTC whatever offset it was given' {
        InModuleScope TestEnvironment {
            ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::new(2026, 8, 27, 14, 0, 0, [TimeSpan]::FromHours(2))) | Should-Be '20260827120000Z'
        }
    }

    It 'round-trips' {
        InModuleScope TestEnvironment {
            $ticks = [DateTime]::UtcNow.Ticks
            $now = [DateTimeOffset]::new($ticks - ($ticks % [TimeSpan]::TicksPerSecond), [TimeSpan]::Zero)
            (ConvertFrom-FreeIPADateTime -Value (ConvertTo-FreeIPADateTime -Value $now)).UtcTicks | Should-Be $now.UtcTicks
        }
    }
}

Describe 'Get-FreeIPAMemberFailure' -Tag 'Unit', 'Private' {

    It 'flattens the failed tree into kind, name and reason, and is empty when nothing failed' {
        InModuleScope TestEnvironment {
            $outcome = '{"completed": 1, "failed": {"member": {"user": [["jnino", "This entry is already a member"]], "group": []}}}' | ConvertFrom-Json
            Get-FreeIPAMemberFailure -Outcome $outcome | Should-BeCollection @('user jnino: This entry is already a member')
            @(Get-FreeIPAMemberFailure -Outcome ('{"completed": 2, "failed": {"member": {"user": []}}}' | ConvertFrom-Json)) | Should-BeCollection -Count 0
            @(Get-FreeIPAMemberFailure -Outcome $null) | Should-BeCollection -Count 0
        }
    }
}

Describe 'Test-FreeIPAPrerequisite' -Tag 'Unit', 'Private' {

    It 'names every seed file a step actually reads' {
        InModuleScope TestEnvironment {
            # Derived from the source, so a step added with a new file cannot pass the check
            # and fail halfway through a seed.
            $root = $script:TestEnvironmentProvider['FreeIPA'].Root
            $referenced = @(Get-ChildItem -Path (Join-Path $root 'Public'), (Join-Path $root 'Private') -Filter *.ps1 |
                    Where-Object { $_.Name -ne 'Test-FreeIPAPrerequisite.ps1' } |
                    ForEach-Object { [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw), "'(FreeIPA[A-Za-z]+\.csv)'") | ForEach-Object { $_.Groups[1].Value } } |
                    Sort-Object -Unique)
            $referenced.Count | Should-BeGreaterThan 0

            $listed = @([regex]::Matches((Get-Content -LiteralPath (Join-Path $root 'Private\Test-FreeIPAPrerequisite.ps1') -Raw), "'(FreeIPA[A-Za-z]+\.csv)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            $listed | Should-BeCollection $referenced
        }
    }

    It 'fails without a connection and passes with one and every file present' {
        InModuleScope TestEnvironment {
            $script:FreeIPAConnection = $null
            (Test-FreeIPAPrerequisite -CheckDataFiles -ErrorAction SilentlyContinue) | Should-BeFalse
            $script:FreeIPAConnection = @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-' }
            (Test-FreeIPAPrerequisite -CheckDataFiles) | Should-BeTrue
            $script:FreeIPAConnection = $null
        }
    }
}
