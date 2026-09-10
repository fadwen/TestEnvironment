#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Disconnect-OktaEnvironment is four lines, and the reason it gets its own suite is that
    all four are about a live credential.

    Until it runs, an SSWS token or a bearer token sits in a module-scoped variable that
    anything else in the session can read. So the properties worth pinning are that it actually
    clears (rather than clearing a copy), that it is honest under -WhatIf rather than reporting
    success while leaving the credential in place, and that calling it when nothing is connected
    is a no-op rather than an error - because the natural place to put it is a finally block,
    where throwing would mask whatever really went wrong.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Disconnect-OktaEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            $script:OktaConnection = @{
                OrgUrl              = 'https://trial-1.okta.com'
                AuthorizationHeader = 'SSWS a-real-looking-token'
                AuthType            = 'ApiToken'
                Prefix              = 'OKTALAB'
                EmailDomain         = 'oktalab.example.com'
            }
        }
    }

    It 'clears the stored credential' {
        InModuleScope TestEnvironment {
            Disconnect-OktaEnvironment -Confirm:$false

            Get-OktaConnection -AllowNone | Should-BeNull
        }
    }

    It 'leaves no Authorization header behind anywhere in module state' {
        # Clearing a copy rather than the variable itself would pass the test above while the
        # token stayed readable.
        InModuleScope TestEnvironment {
            Disconnect-OktaEnvironment -Confirm:$false

            $script:OktaConnection | Should-BeNull
        }
    }

    It 'makes the next call demand a reconnection rather than failing obscurely' {
        InModuleScope TestEnvironment {
            Disconnect-OktaEnvironment -Confirm:$false

            { Get-OktaConnection } | Should-Throw -ExceptionMessage '*Connect-OktaEnvironment*'
        }
    }

    It 'keeps the credential under -WhatIf' {
        # A disconnect that reports success under -WhatIf while leaving a live token in the
        # session is the worst possible direction for this particular function to be wrong in.
        InModuleScope TestEnvironment {
            Disconnect-OktaEnvironment -WhatIf

            (Get-OktaConnection).AuthorizationHeader | Should-Be 'SSWS a-real-looking-token'
        }
    }

    It 'is a no-op when nothing is connected' {
        # It belongs in a finally block, where throwing would mask the real failure.
        InModuleScope TestEnvironment {
            $script:OktaConnection = $null

            Disconnect-OktaEnvironment -Confirm:$false

            Get-OktaConnection -AllowNone | Should-BeNull
            Should-NotInvoke Write-TestMessage
        }
    }

    It 'names the org it is disconnecting from' {
        InModuleScope TestEnvironment {
            Disconnect-OktaEnvironment -Confirm:$false
            Should-Invoke Write-TestMessage -Times 1 -Exactly
        }
    }
}
