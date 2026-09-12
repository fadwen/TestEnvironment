#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The safeguards that exist because of a real run. A lab domain had two domain controllers
    registered and one of them had been switched off for three weeks. Automatic discovery
    handed back the dead one part way through a seed, so the first three steps succeeded and
    every step after them failed with the same error, twenty-five times for the service
    accounts alone, and the directory was left half built.

    Two things stop that happening again, and both are pinned here. The connection picks a
    domain controller that actually answers and every later call is aimed at it, so discovery
    cannot change its mind halfway. And if the chosen one stops answering anyway, the run
    stops on the spot rather than reporting the same failure once per object.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Select-ADTestServer' -Tag 'Unit', 'Private', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            # Only these two answer. The domain also registers a third that is switched off,
            # which is the case the whole function exists for.
            $script:Alive = @('pdc.contoso.com', 'dc03.contoso.com')
            Mock Get-ADDomain {
                if ($Server -and $script:Alive -notcontains $Server) {
                    throw 'Unable to find a default server with Active Directory Web Services running.'
                }
                [PSCustomObject]@{
                    DNSRoot                        = 'contoso.com'
                    PDCEmulator                    = 'pdc.contoso.com'
                    ReplicaDirectoryServers        = @('dead.contoso.com', 'pdc.contoso.com', 'dc03.contoso.com')
                    ReadOnlyReplicaDirectoryServers = @()
                }
            }
        }
    }

    It 'uses the server it was given, and treats its silence as fatal rather than looking elsewhere' {
        InModuleScope TestEnvironment {
            Select-ADTestServer -Server 'dc03.contoso.com' | Should-Be 'dc03.contoso.com'
            # Somebody who names a domain controller means it, so falling back would be wrong.
            { Select-ADTestServer -Server 'dead.contoso.com' } |
                Should-Throw -ExceptionMessage '*did not answer*'
        }
    }

    It 'prefers the PDC emulator when nothing was asked for' {
        InModuleScope TestEnvironment {
            Select-ADTestServer | Should-Be 'pdc.contoso.com'
        }
    }

    It 'skips a registered controller that does not answer and returns one that does' {
        InModuleScope TestEnvironment {
            # The failure this was written for: the PDC itself is the dead one.
            $script:Alive = @('dc03.contoso.com')
            Select-ADTestServer | Should-Be 'dc03.contoso.com'
        }
    }

    It 'falls back to the DNS records when discovery itself cannot answer' {
        InModuleScope TestEnvironment {
            $script:Alive = @('dc03.contoso.com')
            Mock Get-ADDomain {
                if (-not $Server -or $script:Alive -notcontains $Server) {
                    throw 'Unable to find a default server with Active Directory Web Services running.'
                }
                [PSCustomObject]@{ DNSRoot = 'contoso.com' }
            }
            Mock Resolve-DnsName {
                @(
                    [PSCustomObject]@{ NameTarget = 'dead.contoso.com' }
                    [PSCustomObject]@{ NameTarget = 'dc03.contoso.com' }
                )
            }
            $env:USERDNSDOMAIN = 'contoso.com'
            Select-ADTestServer | Should-Be 'dc03.contoso.com'
        }
    }

    It 'says which controllers it tried when none of them answer' {
        InModuleScope TestEnvironment {
            $script:Alive = @()
            Mock Resolve-DnsName { @() }
            { Select-ADTestServer } | Should-Throw -ExceptionMessage '*None of the*answered*'
        }
    }
}

Describe 'Set-ADTestServerPin' -Tag 'Unit', 'Private', 'Safety' {

    AfterEach {
        InModuleScope TestEnvironment { Set-ADTestServerPin -Clear }
    }

    It 'aims every AD and DNS call at one controller without touching the caller''s session' {
        $before = $PSDefaultParameterValues.Count

        InModuleScope TestEnvironment {
            Set-ADTestServerPin -Server 'dc01.contoso.com'
            $script:PSDefaultParameterValues['*-AD*:Server'] | Should-Be 'dc01.contoso.com'
            $script:PSDefaultParameterValues['*-DnsServer*:ComputerName'] | Should-Be 'dc01.contoso.com'
        }

        # Module scope, so nothing is written into the session that imported the module.
        $PSDefaultParameterValues.Count | Should-Be $before
    }

    It 'replaces a previous pin rather than stacking, and clears completely' {
        InModuleScope TestEnvironment {
            Set-ADTestServerPin -Server 'first.contoso.com'
            Set-ADTestServerPin -Server 'second.contoso.com'
            $script:PSDefaultParameterValues['*-AD*:Server'] | Should-Be 'second.contoso.com'

            Set-ADTestServerPin -Clear
            $script:PSDefaultParameterValues.ContainsKey('*-AD*:Server') | Should-BeFalse
            $script:PSDefaultParameterValues.ContainsKey('*-DnsServer*:ComputerName') | Should-BeFalse
        }
    }

    It 'is cleared by disconnecting, so the next connection is not aimed at the last one' {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Set-ADTestServerPin -Server 'dc01.contoso.com'
            Disconnect-ADEnvironment
            $script:PSDefaultParameterValues.ContainsKey('*-AD*:Server') | Should-BeFalse
        }
    }
}

Describe 'Test-ADTestDirectoryReachable' -Tag 'Unit', 'Private' {

    It 'is true when the directory answers and false when it does not, without throwing' {
        InModuleScope TestEnvironment {
            Mock Get-ADDomain { [PSCustomObject]@{ DNSRoot = 'contoso.com' } }
            Test-ADTestDirectoryReachable | Should-BeTrue

            Mock Get-ADDomain { throw 'Unable to find a default server with Active Directory Web Services running.' }
            Test-ADTestDirectoryReachable | Should-BeFalse
        }
    }
}
