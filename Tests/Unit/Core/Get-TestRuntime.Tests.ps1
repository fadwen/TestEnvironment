#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one place the edition is read. What has to hold: every capability is detected on the
    cmdlet that has it, so the flags agree with Get-Command on whichever PowerShell runs the
    suite; the HTTP decisions follow the flags; the result is computed once and cached; and the
    exported command returns the same object.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'Get-TestRuntime' -Tag 'Unit', 'Private' {

    It 'reports the edition and version the session runs, and a platform' {
        InModuleScope TestEnvironment {
            $runtime = Get-TestRuntime
            $runtime.PSObject.TypeNames[0] | Should-Be 'TestEnvironmentRuntime'
            $runtime.Edition | Should-Be $PSVersionTable.PSEdition
            $runtime.Version | Should-Be ([version]$PSVersionTable.PSVersion)
            (@('Windows', 'Linux', 'macOS') -contains $runtime.Platform) | Should-BeTrue
            $runtime.Parallel | Should-Be 'RunspacePool'
        }
    }

    It 'detects each HTTP capability on Invoke-WebRequest itself, never from the version' {
        InModuleScope TestEnvironment {
            $real = @((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet).Parameters.Keys)
            $runtime = Get-TestRuntime -Refresh
            $runtime.Capability.SkipHttpErrorCheck | Should-Be ($real -contains 'SkipHttpErrorCheck')
            $runtime.Capability.HttpTimeouts | Should-Be ($real -contains 'ConnectionTimeoutSeconds')
            $runtime.Capability.JsonAsHashtable | Should-Be (@((Get-Command -Name ConvertFrom-Json -CommandType Cmdlet).Parameters.Keys) -contains 'AsHashtable')
            $runtime.Capability.ModernTls | Should-Be ($PSVersionTable.PSEdition -eq 'Core')
        }
    }

    It 'decides the HTTP methods from the capabilities' {
        InModuleScope TestEnvironment {
            $runtime = Get-TestRuntime
            $runtime.Http.ErrorBody | Should-Be $(if ($runtime.Capability.SkipHttpErrorCheck) { 'SkipHttpErrorCheck' } else { 'ResponseStream' })
            # Tried and measured at no gain, so not a decision the object makes.
            $runtime.Http.PSObject.Properties['Version'] | Should-BeNull
            $runtime.Capability.PSObject.Properties['HttpVersion'] | Should-BeNull
            $runtime.Http.Tls | Should-Be $(if ($runtime.Capability.ModernTls) { 'Default' } else { 'Tls12Added' })
            # The same on both editions, and listed so the object says everything the layer does.
            $runtime.Http.Encoding | Should-Be 'Utf8Bytes'
            $runtime.Http.Progress | Should-Be 'Suppressed'
        }
    }

    It 'is computed once and cached in module scope' {
        InModuleScope TestEnvironment {
            $first = Get-TestRuntime
            [object]::ReferenceEquals($first, (Get-TestRuntime)) | Should-BeTrue
            [object]::ReferenceEquals($first, $script:TestEnvironmentRuntime) | Should-BeTrue
            [object]::ReferenceEquals($first, (Get-TestRuntime -Refresh)) | Should-BeFalse
        }
    }

    It 'is what the exported command returns' {
        $exported = Get-TestEnvironmentRuntime
        $exported.PSObject.TypeNames[0] | Should-Be 'TestEnvironmentRuntime'
        (@('SkipHttpErrorCheck', 'ResponseStream') -contains $exported.Http.ErrorBody) | Should-BeTrue
    }
}
