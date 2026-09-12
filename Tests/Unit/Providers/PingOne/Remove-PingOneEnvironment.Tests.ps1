#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown safety for the PingOne provider.

    Two failure modes are pinned here, because neither produces an error:

    1. -Force defeating -WhatIf. A guard written "if ($Force -or ShouldProcess(...))"
       short-circuits, and "Remove-... -Force -WhatIf" really deletes. The only way to catch it
       is a test asserting that nothing was deleted.

    2. A confirmation that does not stop anything. A refusal handled by returning from begin{}
       ends that block and nothing else, so the deletion goes ahead - and a non-interactive
       session, which cannot answer, always takes that path.

    Every call is mocked. This suite must never reach an environment.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-PingOneEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-PingOneConnection {
                @{
                    EnvironmentId   = '00000000-0000-4000-8000-000000000001'
                    EnvironmentName = 'Test'
                    Prefix          = 'ZZ-TEST-'
                    EmailDomain     = 'pingonelab.example.com'
                }
            }
            Mock Write-TestMessage { }

            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Applications' } { @([PSCustomObject]@{ id = 'a1'; name = 'ZZ-TEST-App' }) }
            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Resources' } { @([PSCustomObject]@{ id = 'r1'; name = 'ZZ-TEST-Api' }) }
            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Users' } { @([PSCustomObject]@{ id = 'u1'; username = 'zz-test-ada' }) }
            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Groups' } { @([PSCustomObject]@{ id = 'g1'; name = 'ZZ-TEST-Group' }) }
            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Populations' } { @([PSCustomObject]@{ id = 'p1'; name = 'ZZ-TEST-Staff' }) }
            Mock Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Attributes' } { @([PSCustomObject]@{ id = 't1'; name = 'zzTestSeedTag'; SchemaId = 's1' }) }

            $script:Deleted = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-PingOneRequest -ParameterFilter { $Method -eq 'DELETE' } {
                $script:Deleted.Add($Path)
            }
        }
    }

    Context 'WhatIf wins over Force' {

        It 'deletes nothing with -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-PingOneEnvironment -Force -WhatIf 6>$null
                Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'DELETE' }
            }
        }

        It 'reports nothing removed under -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $result = Remove-PingOneEnvironment -Force -WhatIf -PassThru 6>$null
                $result.TotalRemoved | Should-Be 0
            }
        }

        It 'previews without -Force rather than treating the preview as a refusal' {
            # Asking for an answer before showing what would happen made -WhatIf unusable from
            # anything non-interactive. A preview must skip the question, list what it would
            # remove, and remove none of it.
            InModuleScope TestEnvironment {
                $result = Remove-PingOneEnvironment -WhatIf -PassThru 6>$null
                $result.Cancelled | Should-BeFalse
                Should-Invoke Get-PingOneSeededObject -ParameterFilter { $Type -eq 'Users' }
                Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'DELETE' }
            }
        }
    }

    Context 'A refusal actually stops the run' {

        It 'deletes nothing when there is no -Force and nobody can answer the prompt' {
            # A test host cannot answer ShouldContinue. That must read as a refusal, which is
            # exactly what an unattended run is.
            InModuleScope TestEnvironment {
                $null = Remove-PingOneEnvironment 6>$null
                Should-NotInvoke Invoke-PingOneRequest -ParameterFilter { $Method -eq 'DELETE' }
            }
        }

        It 'reports the cancellation, with nothing removed' {
            InModuleScope TestEnvironment {
                $result = Remove-PingOneEnvironment -PassThru 6>$null
                $result.Cancelled | Should-BeTrue
                $result.TotalRemoved | Should-Be 0
            }
        }

        It 'does not even enumerate what it would remove once refused' {
            InModuleScope TestEnvironment {
                $null = Remove-PingOneEnvironment 6>$null
                Should-NotInvoke Get-PingOneSeededObject
            }
        }
    }

    Context 'Force removes, in the only order PingOne accepts' {

        It 'removes one of each type with -Force' {
            InModuleScope TestEnvironment {
                $result = Remove-PingOneEnvironment -Force -PassThru 6>$null
                $result.Cancelled | Should-BeFalse
                $result.TotalRemoved | Should-Be 6
            }
        }

        It 'removes applications before resources, users before populations, and attributes last' {
            # Populations can only be deleted empty, and PingOne refuses to delete a custom
            # attribute while a user still holds a value in it.
            InModuleScope TestEnvironment {
                $null = Remove-PingOneEnvironment -Force 6>$null
                $order = @($script:Deleted)

                $index = {
                    param($Start)
                    for ($i = 0; $i -lt $order.Count; $i++) { if ($order[$i].StartsWith($Start)) { return $i } }
                    return -1
                }

                (& $index 'applications/') | Should-BeLessThan (& $index 'resources/')
                (& $index 'users/') | Should-BeLessThan (& $index 'populations/')
                (& $index 'groups/') | Should-BeLessThan (& $index 'populations/')
                $order[-1] | Should-MatchString '^schemas/.+/attributes/'
            }
        }
    }

    Context 'Keep' {

        It 'leaves the kept type alone' {
            InModuleScope TestEnvironment {
                $null = Remove-PingOneEnvironment -Force -Keep Applications 6>$null
                @($script:Deleted | Where-Object { $_ -like 'applications/*' }) | Should-BeCollection -Count 0
            }
        }

        It 'refuses to remove populations or attributes while keeping the users that depend on them' {
            InModuleScope TestEnvironment {
                $result = Remove-PingOneEnvironment -Force -Keep Users -PassThru 6>$null
                @($script:Deleted | Where-Object { $_ -like 'populations/*' }) | Should-BeCollection -Count 0
                @($script:Deleted | Where-Object { $_ -like 'schemas/*' }) | Should-BeCollection -Count 0
                @($result.Errors).Count | Should-BeGreaterThan 0
            }
        }
    }
}
