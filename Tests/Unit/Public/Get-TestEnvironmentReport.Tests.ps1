#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The shared surface, held to by contract rather than by habit. Every provider's report takes
    the same three parameters with the same format set, so -OutputFormat JSON -OutputPath x
    -PassThru means the same thing whichever directory is connected; every provider that stores a
    credential answers to -UseStoredCredential as well as its own name for it, so one script can
    reconnect to any of them; and the dispatchers forward what they were given. These are driven
    off the Providers folder, so a seventh provider is held to them the day its folder appears.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $script:ModuleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'The shared command surface' -Tag 'Unit', 'Contract' {

    BeforeDiscovery {
        $script:Provider = @(Get-ChildItem -Path (Join-Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) 'Providers') -Directory |
                ForEach-Object { @{ Name = $_.Name } })
    }

    It 'the <Name> report takes -OutputFormat Console, JSON, HTML or CSV, -OutputPath and -PassThru' -ForEach $script:Provider {
        InModuleScope TestEnvironment -Parameters @{ Provider = $Name } {
            param($Provider)
            $command = Get-Command -Name ('Get-{0}EnvironmentReport' -f $Provider)
            $command.Parameters.Keys | Should-ContainCollection @('OutputFormat', 'OutputPath', 'PassThru')
            $set = @($command.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0]
            @($set.ValidValues | Sort-Object) | Should-BeCollection @('Console', 'CSV', 'HTML', 'JSON')
            $command.Parameters['PassThru'].ParameterType | Should-Be ([switch])
        }
    }

    It 'the <Name> connect answers to -UseStoredCredential when it stores a credential at all' -ForEach $script:Provider {
        InModuleScope TestEnvironment -Parameters @{ Provider = $Name } {
            param($Provider)
            $command = Get-Command -Name ('Connect-{0}Environment' -f $Provider)
            # Active Directory connects as the caller's own identity and stores nothing.
            if ($Provider -eq 'AD') {
                $command.Parameters.Keys | Should-NotContainCollection 'UseStoredCredential'
                return
            }
            $stored = @($command.Parameters.Values | Where-Object { $_.Aliases -contains 'UseStoredCredential' })
            $stored.Count | Should-Be 1
            $stored[0].ParameterType | Should-Be ([switch])
        }
    }
}

Describe 'Get-TestEnvironmentReport' -Tag 'Unit', 'Public' {

    AfterEach {
        InModuleScope TestEnvironment { $script:ActiveProvider = $null }
    }

    It 'refuses to run before anything is connected' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = $null
            { Get-TestEnvironmentReport } | Should-Throw -ExceptionMessage '*Not connected*'
        }
    }

    It 'forwards the shared parameters to the connected provider, by their shared names and by the Entra aliases' {
        InModuleScope TestEnvironment {
            $script:ActiveProvider = 'Entra'
            Mock Get-EntraEnvironmentReport { }

            Get-TestEnvironmentReport -OutputFormat JSON -OutputPath 'x.json' -PassThru
            Should-Invoke Get-EntraEnvironmentReport -Times 1 -Exactly -ParameterFilter { $OutputFormat -eq 'JSON' -and $OutputPath -eq 'x.json' -and $PassThru }

            # The names the Entra report had before the surface was unified still bind.
            Get-TestEnvironmentReport -Format HTML -Path 'x.html'
            Should-Invoke Get-EntraEnvironmentReport -Times 1 -Exactly -ParameterFilter { $OutputFormat -eq 'HTML' -and $OutputPath -eq 'x.html' }
        }
    }
}

Describe 'Connect-TestEnvironment' -Tag 'Unit', 'Public' {

    AfterEach {
        InModuleScope TestEnvironment { $script:ActiveProvider = $null }
    }

    It 'binds -UseStoredCredential to the provider''s own switch for it' {
        InModuleScope TestEnvironment {
            # The dispatcher treats an empty return as a failed connection, so the mocks hand back one.
            Mock Connect-PingOneEnvironment { [PSCustomObject]@{ PSTypeName = 'PingOneConnection'; EnvironmentId = $EnvironmentId } }
            Mock Connect-AuthentikEnvironment { [PSCustomObject]@{ PSTypeName = 'AuthentikConnection'; BaseUrl = $BaseUrl } }

            $environment = '0e2469df-9492-43bf-b8d6-8b9023795e55'
            Connect-TestEnvironment -Provider PingOne -EnvironmentId $environment -ClientId 'bb016fd3-0157-40ac-8ca3-74eda168d0d9' -UseStoredCredential
            Should-Invoke Connect-PingOneEnvironment -Times 1 -Exactly -ParameterFilter { $UseStoredSecret -and $EnvironmentId -eq $environment }

            Connect-TestEnvironment -Provider Authentik -BaseUrl 'https://auth.example.com' -UseStoredCredential
            Should-Invoke Connect-AuthentikEnvironment -Times 1 -Exactly -ParameterFilter { $ServiceAccount }
        }
    }
}
