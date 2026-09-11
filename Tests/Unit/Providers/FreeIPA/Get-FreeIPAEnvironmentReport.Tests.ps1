#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The report is what a person reads to know what the seed built, and its promises are
    pinned: every section present in the one shared order, users from all three containers
    folded into one list with their lifecycle named, the class shown without the tag, the
    marker stripped from descriptions, memberships limited to seeded groups, a preserved user
    called preserved and a locked one disabled, enrolment read from has_keytab, and every file
    format written as UTF-8 so the accented names survive.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-FreeIPAEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; AuthType = 'ServiceAccount' } }
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Get-FreeIPASeededObject {
                switch ($Type) {
                    'Users' {
                        @(
                            [PSCustomObject]@{ uid = @('jnino'); cn = @('José Niño'); userclass = @('ZZ-TEST-seed', 'employee'); title = @('Platform Engineer'); ou = @('Engineering'); manager = @('awhitfield'); memberof_group = @('zz-test-all-staff', 'ipausers'); ipauserauthtype = @('otp'); krbpasswordexpiration = @([PSCustomObject]@{ __datetime__ = '20261210024734Z' }); ipasshpubkey = @('ssh-ed25519 AAAA'); nsaccountlock = $false }
                            [PSCustomObject]@{ uid = @('talvarez'); cn = @('Tomás Álvarez'); userclass = @('ZZ-TEST-seed', 'employee'); memberof_group = @('zz-test-dept-sales'); nsaccountlock = $true }
                        )
                    }
                    'PreservedUsers' { @([PSCustomObject]@{ uid = @('rokafor'); cn = @('Rita Okafor'); userclass = @('ZZ-TEST-seed', 'employee') }) }
                    'StagedUsers' { @([PSCustomObject]@{ uid = @('lchen'); cn = @('Lin Chen'); userclass = @('ZZ-TEST-seed', 'employee') }) }
                    'Groups' { @([PSCustomObject]@{ cn = @('zz-test-team-platform'); description = @('Platform engineering team [ZZ-TEST-seed]'); objectclass = @('top', 'groupofnames', 'ipausergroup'); member_user = @('jnino', 'zmueller'); memberof_group = @('zz-test-dept-engineering') }, [PSCustomObject]@{ cn = @('zz-test-ext-partners'); description = @('x [ZZ-TEST-seed]'); objectclass = @('ipaexternalgroup', 'posixgroup') }) }
                    'Hostgroups' { @([PSCustomObject]@{ cn = @('zz-test-web-servers'); description = @('Web front ends [ZZ-TEST-seed]'); member_host = @('zz-test-web01.ipa.example.com'); memberof_hostgroup = @('zz-test-all-servers') }) }
                    'Hosts' { @([PSCustomObject]@{ fqdn = @('zz-test-db01.ipa.example.com'); description = @('Primary database [ZZ-TEST-seed]'); nsosversion = @('RHEL 9.4'); userclass = @('ZZ-TEST-seed', 'server'); memberof_hostgroup = @('zz-test-db-servers'); managedby_host = @('zz-test-db01.ipa.example.com', 'zz-test-web01.ipa.example.com'); has_keytab = $false }) }
                    'HbacRules' {
                        @(
                            [PSCustomObject]@{ cn = @('zz-test-legacy-open-door'); description = @('Anyone [ZZ-TEST-seed]'); ipaenabledflag = @($false); usercategory = @('all'); hostcategory = @('all'); servicecategory = @('all') }
                            [PSCustomObject]@{ cn = @('zz-test-finance-payroll'); description = @('Finance [ZZ-TEST-seed]'); ipaenabledflag = @($true); memberuser_user = @('praghunathan'); memberuser_group = @('zz-test-dept-finance'); memberhost_host = @('zz-test-db01.ipa.example.com'); memberservice_hbacsvcgroup = @('zz-test-finance-apps') }
                        )
                    }
                    'SudoRules' { @([PSCustomObject]@{ cn = @('zz-test-dba-postgres'); ipaenabledflag = @($true); sudoorder = @(20); memberuser_user = @('jnino'); memberhost_host = @('zz-test-db01.ipa.example.com'); memberallowcmd_sudocmd = @('/usr/bin/psql'); ipasudorunasextuser = @('postgres'); ipasudoopt = @('!authenticate') }) }
                    'Roles' { @([PSCustomObject]@{ cn = @('zz-test-lab-helpdesk'); description = @('Lab helpdesk [ZZ-TEST-seed]'); memberof_privilege = @('zz-test-lab-password-reset', 'Password Policy Readers'); member_group = @('zz-test-lab-admins') }) }
                    'PasswordPolicies' { @([PSCustomObject]@{ cn = @('zz-test-dept-sales'); cospriority = @(200); krbmaxpwdlife = @(0); krbpwdminlength = @(8); passwordgracelimit = @(-1) }) }
                    'Services' { @([PSCustomObject]@{ krbcanonicalname = @('postgres/zz-test-db01.ipa.example.com@IPA.EXAMPLE.COM'); managedby_host = @('zz-test-db01.ipa.example.com', 'zz-test-web01.ipa.example.com'); has_keytab = $false }) }
                    'ServiceDelegationRules' { @([PSCustomObject]@{ cn = @('zz-test-web-to-ldap'); memberprincipal = @('HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM'); ipaallowedtarget_servicedelegationtarget = @('zz-test-ldap-targets') }) }
                    'ServiceDelegationTargets' { @([PSCustomObject]@{ cn = @('zz-test-ldap-targets'); memberprincipal = @('ldap/zz-test-legacy01.ipa.example.com@IPA.EXAMPLE.COM') }) }
                    default { @() }
                }
            }
        }
    }

    It 'folds every container into one users list with the lifecycle named and the tag stripped from the class' {
        InModuleScope TestEnvironment {
            $r = Get-FreeIPAEnvironmentReport -PassThru
            @($r.Users.Login) | Should-BeCollection @('jnino', 'lchen', 'rokafor', 'talvarez')
            ($r.Users | Where-Object Login -eq 'jnino').Lifecycle | Should-Be 'Active'
            ($r.Users | Where-Object Login -eq 'talvarez').Lifecycle | Should-Be 'Disabled'
            ($r.Users | Where-Object Login -eq 'rokafor').Lifecycle | Should-Be 'Preserved'
            ($r.Users | Where-Object Login -eq 'lchen').Lifecycle | Should-Be 'Staged'
            $jose = $r.Users | Where-Object Login -eq 'jnino'
            $jose.Class | Should-Be 'employee'
            $jose.Groups | Should-Be 'zz-test-all-staff'
            $jose.AuthType | Should-Be 'otp'
            $jose.PublicKeys | Should-Be 1
            $jose.PasswordExpires | Should-Be ([DateTime]::new(2026, 12, 10, 2, 47, 34, [DateTimeKind]::Utc))
            $jose.Name | Should-Be 'José Niño'
        }
    }

    It 'types the groups, strips the marker, counts members and reads enrolment from has_keytab' {
        InModuleScope TestEnvironment {
            $r = Get-FreeIPAEnvironmentReport -PassThru
            $team = $r.Groups | Where-Object Name -eq 'zz-test-team-platform'
            $team.Type | Should-Be 'nonposix'
            $team.Description | Should-Be 'Platform engineering team'
            $team.MemberUsers | Should-Be 2
            $team.MemberOf | Should-Be 'zz-test-dept-engineering'
            ($r.Groups | Where-Object Name -eq 'zz-test-ext-partners').Type | Should-Be 'external'
            $r.Hostgroups[0].MemberHosts | Should-Be 1
            $db = $r.Hosts[0]
            $db.Enrolled | Should-BeFalse
            $db.Class | Should-Be 'server'
            $db.ManagedBy | Should-Be 'zz-test-web01.ipa.example.com'
            $db.Description | Should-Be 'Primary database'
        }
    }

    It 'reads a category of all as the clause, names the members otherwise, and calls a disabled rule disabled' {
        InModuleScope TestEnvironment {
            $r = Get-FreeIPAEnvironmentReport -PassThru
            $open = $r.HbacRules | Where-Object Name -eq 'zz-test-legacy-open-door'
            $open.Enabled | Should-BeFalse
            $open.Users | Should-Be 'all'
            $open.Services | Should-Be 'all'
            $payroll = $r.HbacRules | Where-Object Name -eq 'zz-test-finance-payroll'
            $payroll.Enabled | Should-BeTrue
            $payroll.Users | Should-Be 'praghunathan; zz-test-dept-finance'
            $payroll.Services | Should-Be 'zz-test-finance-apps'
            $sudo = $r.SudoRules[0]
            $sudo.RunAsUsers | Should-Be 'postgres'
            $sudo.Options | Should-Be '!authenticate'
            $sudo.Order | Should-Be '20'
            $r.Roles[0].Privileges | Should-Be 'zz-test-lab-password-reset; Password Policy Readers'
            $r.PasswordPolicies[0].GraceLimit | Should-Be '-1'
            $r.Services[0].Host | Should-Be 'zz-test-db01.ipa.example.com'
            $r.Services[0].ManagedBy | Should-Be 'zz-test-web01.ipa.example.com'
            @($r.ServiceDelegation.Kind) | Should-BeCollection @('Rule', 'Target')
            $r.ServiceDelegation[0].Targets | Should-Be 'zz-test-ldap-targets'
        }
    }

    It 'renders every section in the shared order to the console' {
        InModuleScope TestEnvironment {
            $null = Get-FreeIPAEnvironmentReport
            foreach ($section in $script:FreeIPAReportSections) {
                Should-Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "$section (*" }
            }
            $script:FreeIPAReportSections | Should-BeCollection @('Users', 'Groups', 'Hostgroups', 'Hosts', 'Netgroups', 'HbacRules', 'SudoRules', 'Roles', 'PasswordPolicies', 'Services', 'ServiceDelegation')
        }
    }

    It 'writes every file format as UTF-8 and requires a path for one' {
        InModuleScope TestEnvironment {
            { Get-FreeIPAEnvironmentReport -OutputFormat JSON } | Should-Throw -ExceptionMessage '*-OutputPath*'

            $json = Join-Path $TestDrive 'r.json'
            Get-FreeIPAEnvironmentReport -OutputFormat JSON -OutputPath $json
            ([System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8)) | Should-MatchString 'José Niño'

            $html = Join-Path $TestDrive 'r.html'
            Get-FreeIPAEnvironmentReport -OutputFormat HTML -OutputPath $html
            ([System.IO.File]::ReadAllText($html, [System.Text.Encoding]::UTF8)) | Should-MatchString '<h2>Hosts \(1\)</h2>'

            $folder = Join-Path $TestDrive 'csv'
            Get-FreeIPAEnvironmentReport -OutputFormat CSV -OutputPath $folder
            @(Get-ChildItem $folder -Filter 'FreeIPALab*.csv').Count | Should-Be 11
            (Import-Csv (Join-Path $folder 'FreeIPALabUsers.csv') -Encoding UTF8 | Where-Object Login -eq 'jnino').Name | Should-Be 'José Niño'
        }
    }
}
