#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every seeded provider needs the instance's authorization and invalidation flows by primary
    key, and an instance whose defaults were renamed still has flows of those designations.
    Pinned: the default slug is preferred, any flow of the designation is the fallback, an
    instance with neither refuses with the slug to restore, and the answer is cached per
    session so three hundred providers do not mean three hundred lookups.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AuthentikFlow' -Tag 'Unit', 'Private' {

    It 'prefers the default flow by slug' {
        InModuleScope TestEnvironment {
            $connection = @{ BaseUrl = 'https://auth.example.com' }
            Mock Invoke-AuthentikRequest {
                if ($Query['slug'] -eq 'default-provider-authorization-implicit-consent') { return @([PSCustomObject]@{ pk = 'flow-default'; slug = $Query['slug'] }) }
                @([PSCustomObject]@{ pk = 'flow-other'; slug = 'custom' })
            }

            Get-AuthentikFlow -Designation authorization -Connection $connection | Should-Be 'flow-default'
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Query.ContainsKey('designation') }
        }
    }

    It 'falls back to any flow of the designation when the default slug is gone' {
        InModuleScope TestEnvironment {
            $connection = @{ BaseUrl = 'https://auth.example.com' }
            Mock Invoke-AuthentikRequest {
                if ($Query.ContainsKey('slug')) { return @() }
                @([PSCustomObject]@{ pk = 'flow-renamed'; slug = 'our-invalidation' })
            }

            Get-AuthentikFlow -Designation invalidation -Connection $connection | Should-Be 'flow-renamed'
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Query['designation'] -eq 'invalidation' }
        }
    }

    It 'refuses with the slug to restore when the instance has no such flow' {
        InModuleScope TestEnvironment {
            $connection = @{ BaseUrl = 'https://auth.example.com' }
            Mock Invoke-AuthentikRequest { @() }
            { Get-AuthentikFlow -Designation authorization -Connection $connection } | Should-Throw -ExceptionMessage '*default-provider-authorization-implicit-consent*'
        }
    }

    It 'looks each designation up once per session' {
        InModuleScope TestEnvironment {
            $connection = @{ BaseUrl = 'https://auth.example.com' }
            Mock Invoke-AuthentikRequest { @([PSCustomObject]@{ pk = "flow-$($Query['slug'])"; slug = $Query['slug'] }) }

            1..3 | ForEach-Object { $null = Get-AuthentikFlow -Designation authorization -Connection $connection }
            $null = Get-AuthentikFlow -Designation invalidation -Connection $connection

            Should-Invoke Invoke-AuthentikRequest -Times 2 -Exactly
        }
    }
}
