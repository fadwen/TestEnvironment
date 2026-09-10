#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A rule names its transports by primary key, so the transport has to exist first and a
    re-run has to find it rather than make another. Both are pinned, with the flags a report
    has to show.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikNotificationRule' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject { @() }

            $script:Order = [System.Collections.Generic.List[string]]::new()
            $script:Bodies = @{}
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST') {
                    $script:Order.Add($Path)
                    $script:Bodies[$Body.name] = $Body
                    return [PSCustomObject]@{ pk = "pk-$($Body.name)"; name = $Body.name }
                }
                return $null
            }
        }
    }

    It 'creates the transport before the rule that references it' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikNotificationRule -RuleName 'Alert Relay' -PassThru -Confirm:$false

            $r.CreatedRules | Should-Be 1
            $r.TransportsCreated | Should-Be 1
            $script:Order | Should-BeCollection @('/events/transports/', '/events/rules/')
            $script:Bodies['ZZ-TEST-Alert Relay'].transports | Should-BeCollection @('pk-ZZ-TEST-Alert Webhook')
            $script:Bodies['ZZ-TEST-Alert Relay'].severity | Should-Be 'alert'
            $script:Bodies['ZZ-TEST-Alert Webhook'].send_once | Should-BeTrue
            $script:Bodies['ZZ-TEST-Alert Webhook'].mode | Should-Be 'webhook'
        }
    }

    It 'reuses a transport that already exists' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'NotificationTransports') { return @([PSCustomObject]@{ pk = 'existing-t'; name = 'ZZ-TEST-Lifecycle Webhook' }) }
                @()
            }

            $r = New-AuthentikNotificationRule -RuleName 'Lifecycle Watcher' -PassThru -Confirm:$false

            $r.TransportsCreated | Should-Be 0
            $script:Bodies['ZZ-TEST-Lifecycle Watcher'].transports | Should-BeCollection @('existing-t')
        }
    }

    It 'creates both rules and both transports by default' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikNotificationRule -PassThru -Confirm:$false
            $r.CreatedRules | Should-Be 2
            $r.TransportsCreated | Should-Be 2
        }
    }
}
