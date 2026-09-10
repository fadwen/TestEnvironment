#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The report is how every claim the seed makes is read back, so a report that mis-states the
    estate is worse than none. Pinned: every section is present in the one shared order, grants
    and policy bindings are folded in from the bindings on each seeded target, an expired token
    is called expired whether the API hands the timestamp back as a DateTime or a string, an
    undeployed outpost is called undeployed, only what the discovery helper returned is
    reported, and every file format writes UTF-8 so an accented name survives.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AuthentikEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ServiceAccount'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Write-TestMessage { }
            Mock Write-Host { }

            $script:Fixture = @{
                Users                  = @(
                    [PSCustomObject]@{ pk = 1; username = 'zmueller'; name = ('Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'); type = 'internal'; is_active = $true; groups = @('g-eng'); attributes = [PSCustomObject]@{ labDepartment = 'Engineering'; labClearanceLevel = 'Secret'; labIsContractor = $false; labRiskScore = 28 } }
                    [PSCustomObject]@{ pk = 2; username = 'hkobayashi'; name = 'Hana Kobayashi'; type = 'external'; is_active = $true; groups = @('g-con'); attributes = [PSCustomObject]@{ labIsContractor = $true } }
                )
                Groups                 = @(
                    [PSCustomObject]@{ pk = 'g-eng'; name = 'ZZ-TEST-Department Engineering'; parents = @('g-all'); roles = @('role-1'); attributes = [PSCustomObject]@{ labCategory = 'Department' } }
                    [PSCustomObject]@{ pk = 'g-all'; name = 'ZZ-TEST-All Staff'; parents = @(); roles = @(); attributes = [PSCustomObject]@{ labCategory = 'Organisation' } }
                    [PSCustomObject]@{ pk = 'g-con'; name = 'ZZ-TEST-Contractors'; parents = @(); roles = @(); attributes = [PSCustomObject]@{} }
                )
                Roles                  = @([PSCustomObject]@{ pk = 'role-1'; name = 'ZZ-TEST-Application Auditor' })
                Applications           = @([PSCustomObject]@{ pk = 'app-1'; pbm_uuid = 'pbm-wiki'; name = 'ZZ-TEST-Engineering Wiki'; slug = 'zz-test-wiki'; provider = 7; provider_obj = [PSCustomObject]@{ name = 'ZZ-TEST-Wiki Provider'; verbose_name = 'OAuth2/OpenID Provider' }; meta_launch_url = 'https://wiki.lab.example.com'; meta_hide = $false })
                Outposts               = @(
                    [PSCustomObject]@{ pk = 'o-1'; name = 'ZZ-TEST-Edge Proxy'; type = 'proxy'; providers = @(7); service_connection = $null }
                    [PSCustomObject]@{ pk = 'o-2'; name = 'ZZ-TEST-Deployed One'; type = 'ldap'; providers = @(); service_connection = 'sc-1' }
                )
                Certificates           = @([PSCustomObject]@{ pk = 'kp-1'; name = 'ZZ-TEST-SAML Signing'; cert_subject = 'CN=ZZ-TEST-SAML Signing'; cert_expiry = '2027-09-10T18:00:00Z' })
                Flows                  = @([PSCustomObject]@{ pk = 'f-1'; name = 'ZZ-TEST-Sign in'; slug = 'zz-test-partner-authentication'; designation = 'authentication'; stages = @('s-1', 's-2') })
                Stages                 = @([PSCustomObject]@{ pk = 's-1'; name = 'ZZ-TEST-Identify' }, [PSCustomObject]@{ pk = 's-2'; name = 'ZZ-TEST-Log In' })
                ScopeMappings          = @([PSCustomObject]@{ pk = 'm-1'; name = 'ZZ-TEST-Lab Profile'; scope_name = 'lab_profile'; description = 'Your lab profile' })
                Entitlements           = @([PSCustomObject]@{ pbm_uuid = 'pbm-editor'; name = 'ZZ-TEST-Editor'; app_slug = 'zz-test-wiki' })
                Policies               = @([PSCustomObject]@{ pk = 'pol-deny'; name = 'ZZ-TEST-Deny Contractors'; verbose_name = 'Expression Policy' }, [PSCustomObject]@{ pk = 'pol-login'; name = 'ZZ-TEST-Login Failures'; verbose_name = 'Event Matcher Policy' })
                NotificationRules      = @([PSCustomObject]@{ pk = 'rule-alert'; name = 'ZZ-TEST-Alert Relay'; severity = 'alert'; transports = @('t-1') })
                NotificationTransports = @([PSCustomObject]@{ pk = 't-1'; name = 'ZZ-TEST-Alert Webhook' })
                Tokens                 = @(
                    [PSCustomObject]@{ identifier = 'zz-test-tomas-stale'; user_obj = [PSCustomObject]@{ username = 'talvarez' }; intent = 'app_password'; expiring = $true; expires = [DateTime]::UtcNow.AddDays(-1) }
                    [PSCustomObject]@{ identifier = 'zz-test-ada-cli'; user_obj = [PSCustomObject]@{ username = 'awhitfield' }; intent = 'app_password'; expiring = $true; expires = [DateTime]::UtcNow.AddMinutes(20).ToString('o') }
                    [PSCustomObject]@{ identifier = 'zz-test-reporting-service'; user_obj = [PSCustomObject]@{ username = 'svc-reporting' }; intent = 'api'; expiring = $false; expires = [DateTime]::UtcNow.AddDays(-30) }
                )
                Invitations            = @([PSCustomObject]@{ pk = 'i-1'; name = 'zz-test-new-hire-pending'; expires = [DateTime]::UtcNow.AddDays(14); single_use = $true })
            }
            Mock Get-AuthentikSeededObject { $script:Fixture[$Type] }

            # One binding of each subject kind, on the target it belongs to.
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'GET' -and $Path -eq '/policies/bindings/') {
                    switch ($Query['target']) {
                        'pbm-wiki' { return @([PSCustomObject]@{ pk = 'b1'; group = 'g-eng'; user = $null; policy = $null; order = 0; enabled = $true }, [PSCustomObject]@{ pk = 'b2'; group = $null; user = $null; policy = 'pol-deny'; order = 10; enabled = $false }) }
                        'pbm-editor' { return @([PSCustomObject]@{ pk = 'b3'; group = $null; user = 2; policy = $null; order = 0; enabled = $true }) }
                        'rule-alert' { return @([PSCustomObject]@{ pk = 'b4'; group = $null; user = $null; policy = 'pol-login'; order = 0; enabled = $true }) }
                    }
                }
                @()
            }
        }
    }

    It 'reports every section, in the one shared order' {
        InModuleScope TestEnvironment {
            $r = Get-AuthentikEnvironmentReport -PassThru
            foreach ($section in $script:AuthentikReportSections) { $r.PSObject.Properties[$section] | Should-NotBeNull }
            @($r.PSObject.Properties.Name | Where-Object { $script:AuthentikReportSections -contains $_ }) | Should-BeCollection $script:AuthentikReportSections
        }
    }

    It 'folds the bindings on each target into who is granted what and which policy governs which' {
        InModuleScope TestEnvironment {
            $r = Get-AuthentikEnvironmentReport -PassThru

            $r.Applications[0].GrantedTo | Should-Be 'ZZ-TEST-Department Engineering'
            $r.Entitlements[0].GrantedTo | Should-Be 'hkobayashi'
            ($r.Policies | Where-Object Name -eq 'ZZ-TEST-Deny Contractors').BoundTo | Should-Be 'zz-test-wiki'
            ($r.Policies | Where-Object Name -eq 'ZZ-TEST-Deny Contractors').Enabled | Should-Be 'False'
            ($r.Policies | Where-Object Name -eq 'ZZ-TEST-Login Failures').BoundTo | Should-Be 'ZZ-TEST-Alert Relay'
            $r.NotificationRules[0].Triggers | Should-Be 'ZZ-TEST-Login Failures'
            $r.NotificationRules[0].Transports | Should-Be 'ZZ-TEST-Alert Webhook'
        }
    }

    It 'calls a token expired whether the timestamp arrives as a DateTime or a string, and never a non-expiring one' {
        InModuleScope TestEnvironment {
            $r = Get-AuthentikEnvironmentReport -PassThru
            ($r.Tokens | Where-Object Identifier -eq 'zz-test-tomas-stale').Expired | Should-BeTrue
            ($r.Tokens | Where-Object Identifier -eq 'zz-test-ada-cli').Expired | Should-BeFalse
            ($r.Tokens | Where-Object Identifier -eq 'zz-test-ada-cli').Expires | Should-NotBeNull
            $stale = $r.Tokens | Where-Object Identifier -eq 'zz-test-reporting-service'
            $stale.Expired | Should-BeFalse
            $stale.Expires | Should-BeNull
            $r.Invitations[0].Expires | Should-BeGreaterThan ([DateTime]::UtcNow.AddDays(13))
        }
    }

    It 'names the providers an outpost carries and says whether anything is deployed behind it' {
        InModuleScope TestEnvironment {
            $r = Get-AuthentikEnvironmentReport -PassThru
            ($r.Outposts | Where-Object Name -eq 'ZZ-TEST-Edge Proxy').Providers | Should-Be 'ZZ-TEST-Wiki Provider'
            ($r.Outposts | Where-Object Name -eq 'ZZ-TEST-Edge Proxy').Deployed | Should-BeFalse
            ($r.Outposts | Where-Object Name -eq 'ZZ-TEST-Deployed One').Deployed | Should-BeTrue
            $r.Certificates[0].Expires | Should-BeGreaterThan ([DateTime]::UtcNow)
            $r.Flows[0].Stages | Should-Be 'ZZ-TEST-Identify > ZZ-TEST-Log In'
        }
    }

    It 'resolves memberships, parents and roles by name and counts members from the users' {
        InModuleScope TestEnvironment {
            $r = Get-AuthentikEnvironmentReport -PassThru
            ($r.Users | Where-Object Username -eq 'zmueller').Groups | Should-Be 'ZZ-TEST-Department Engineering'
            ($r.Users | Where-Object Username -eq 'hkobayashi').Contractor | Should-BeTrue
            $eng = $r.Groups | Where-Object Name -eq 'ZZ-TEST-Department Engineering'
            $eng.Parents | Should-Be 'ZZ-TEST-All Staff'
            $eng.MemberCount | Should-Be 1
            $eng.Roles | Should-Be 'ZZ-TEST-Application Auditor'
            $r.Roles[0].Groups | Should-Be 'ZZ-TEST-Department Engineering'
            ($r.Groups | Where-Object Name -eq 'ZZ-TEST-All Staff').MemberCount | Should-Be 0
        }
    }

    It 'includes the service account among the users it reports, and only what discovery returned' {
        InModuleScope TestEnvironment {
            $null = Get-AuthentikEnvironmentReport -PassThru
            Should-Invoke Get-AuthentikSeededObject -Times 1 -Exactly -ParameterFilter { $Type -eq 'Users' -and $IncludeServiceAccount }
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -ne '/policies/bindings/' }
        }
    }

    It 'writes JSON, CSV and HTML as UTF-8 so an accented name survives, and refuses a file format with no path' {
        InModuleScope TestEnvironment {
            $accented = 'Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'

            $json = Join-Path $TestDrive 'report.json'
            $null = Get-AuthentikEnvironmentReport -OutputFormat JSON -OutputPath $json
            [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | Should-MatchString ([regex]::Escape($accented))

            $csv = Join-Path $TestDrive 'csv'
            $null = Get-AuthentikEnvironmentReport -OutputFormat CSV -OutputPath $csv
            @(Get-ChildItem $csv -Filter 'AuthentikLab*.csv').Count | Should-Be $script:AuthentikReportSections.Count
            [System.IO.File]::ReadAllText((Join-Path $csv 'AuthentikLabUsers.csv'), [System.Text.Encoding]::UTF8) | Should-MatchString ([regex]::Escape($accented))

            $html = Join-Path $TestDrive 'report.html'
            $null = Get-AuthentikEnvironmentReport -OutputFormat HTML -OutputPath $html
            $page = [System.IO.File]::ReadAllText($html, [System.Text.Encoding]::UTF8)
            foreach ($section in $script:AuthentikReportSections) { $page | Should-MatchString "<h2>$section \(" }
            $page | Should-MatchString 'charset="utf-8"'

            { Get-AuthentikEnvironmentReport -OutputFormat JSON } | Should-Throw -ExceptionMessage '*OutputPath*'
        }
    }

    It 'prints one heading per section to the console' {
        InModuleScope TestEnvironment {
            $null = Get-AuthentikEnvironmentReport
            foreach ($section in $script:AuthentikReportSections) {
                Should-Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like "$section (*" }
            }
        }
    }
}
