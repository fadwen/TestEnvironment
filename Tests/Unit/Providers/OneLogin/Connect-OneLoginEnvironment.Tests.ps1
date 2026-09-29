#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Connecting, the token, the report and the identity snapshot.

    The connect takes the account the way somebody copies it - a bare name, the host, or the portal
    URL - and keeps the name. It proves the credential before storing the connection, and writes the
    credential record only after that proof, through the shared record writer, so a mistyped secret
    is never saved. The token is the client credentials grant against the account's own host.

    The report has the shape every provider shares and counts an app's roles from the roles, because
    OneLogin's app listing leaves role_ids out. The snapshot keys a person by the username with the
    prefix stripped and calls a suspended or rejected person disabled.

    Everything is mocked. The account is never reached.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') }
}

Describe 'Connect-OneLoginEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:OneLoginConnection = $null
            $script:Secret = ConvertTo-TestSecureString -PlainText 'not-a-real-secret'
            Mock Invoke-OneLoginRequest { , @() }
            Mock Export-OneLoginCredential { }
        }
    }

    AfterEach {
        InModuleScope TestEnvironment { $script:OneLoginConnection = $null }
    }

    It 'reads the account name from a bare name, a host or a portal URL' -ForEach @(
        @{ Given = 'contoso' }, @{ Given = 'Contoso.onelogin.com' }, @{ Given = 'https://contoso.onelogin.com/admin2' }
    ) {
        InModuleScope TestEnvironment -Parameters @{ Given = $Given } {
            param($Given)
            $connection = Connect-OneLoginEnvironment -Subdomain $Given -ClientId 'abc123' -ClientSecret $script:Secret -PassThru
            $connection.Subdomain | Should-Be 'contoso'
            $script:OneLoginConnection.ApiHost | Should-Be 'contoso.onelogin.com'
        }
    }

    It 'refuses something that is not an account name' {
        InModuleScope TestEnvironment {
            { Connect-OneLoginEnvironment -Subdomain 'https://example.com/con toso' -ClientId 'abc' -ClientSecret $script:Secret } |
                Should-Throw -ExceptionMessage '*does not name a OneLogin account*'
        }
    }

    It 'stores nothing, not even the record, when the credential is refused' {
        InModuleScope TestEnvironment {
            Mock Invoke-OneLoginRequest { throw 'Could not get a OneLogin access token: 401' }
            { Connect-OneLoginEnvironment -Subdomain contoso -ClientId 'abc' -ClientSecret $script:Secret -SaveSecret } |
                Should-Throw -ExceptionMessage "*Could not connect to OneLogin account 'contoso'*"
            $script:OneLoginConnection | Should-BeNull
            Should-NotInvoke Export-OneLoginCredential
        }
    }

    It 'writes the record through the shared writer once the connection is proved' {
        InModuleScope TestEnvironment {
            $null = Connect-OneLoginEnvironment -Subdomain contoso -ClientId 'abc123' -ClientSecret $script:Secret -SaveSecret
            Should-Invoke Export-OneLoginCredential -Times 1 -Exactly -ParameterFilter {
                $Subdomain -eq 'contoso' -and $ClientId -eq 'abc123' -and $ClientSecret -eq 'not-a-real-secret' -and $Path -like '*contoso.onelogin.json'
            }
        }
    }

    It 'connects from the stored record with nothing but the account name' {
        InModuleScope TestEnvironment {
            Mock Import-OneLoginCredential { [PSCustomObject]@{ Subdomain = 'contoso'; ClientId = 'stored-id'; ClientSecret = $script:Secret } }
            $connection = Connect-OneLoginEnvironment -Subdomain contoso -UseStoredCredential -PassThru
            $connection.ClientId | Should-Be 'stored-id'
            Should-Invoke Import-OneLoginCredential -Times 1 -Exactly -ParameterFilter { $Path -like '*contoso.onelogin.json' }
        }
    }
}

Describe 'Get-OneLoginAccessToken' -Tag 'Unit', 'Public' {

    It 'asks the account''s own token endpoint for client credentials, with the id and secret as Basic' {
        InModuleScope TestEnvironment {
            $connection = @{ Subdomain = 'contoso'; ApiHost = 'contoso.onelogin.com'; ClientId = 'abc'; ClientSecret = (ConvertTo-TestSecureString -PlainText 's3cret') }
            Mock Invoke-TestWebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"access_token":"tok","expires_in":36000,"account_id":123456,"token_type":"bearer"}' } }

            Get-OneLoginAccessToken -Connection $connection -AsPlainText | Should-Be 'tok'
            $connection.AccountId | Should-Be '123456'
            Should-Invoke Invoke-TestWebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://contoso.onelogin.com/auth/oauth2/v2/token' -and $Method -eq 'POST' -and $Body.grant_type -eq 'client_credentials' -and
                $Headers.Authorization -eq ('Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('abc:s3cret')))
            }

            # Reused until a minute before it expires.
            $null = Get-OneLoginAccessToken -Connection $connection -AsPlainText
            Should-Invoke Invoke-TestWebRequest -Times 1 -Exactly
        }
    }
}

Describe 'Get-OneLoginEnvironmentReport and the identity snapshot' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            # Never the real credential folder.
            Mock Get-OneLoginAppSecretRecord { }
            Mock Get-OneLoginConnection { @{ Subdomain = 'contoso'; AccountId = '123456'; Prefix = 'ZZ-TEST-' } }
            $jose = 'Jos' + [string][char]0xE9
            $script:Fixture = @{
                Attributes = @([PSCustomObject]@{ id = 1; shortname = 'zztest_seed_tag'; name = 'ZZ-TEST seed tag' })
                Users      = @(
                    [PSCustomObject]@{ id = 10; username = 'zz-test-jnino'; firstname = $jose; lastname = 'Nino'; status = 1; state = 1; group_id = 20; manager_user_id = $null; role_ids = @(30); custom_attributes = [PSCustomObject]@{ zztest_contractor = 'false' } }
                    [PSCustomObject]@{ id = 11; username = 'zz-test-mbell'; firstname = 'Marcus'; lastname = 'Bell'; status = 2; state = 1; group_id = $null; manager_user_id = 10; role_ids = @(); custom_attributes = $null }
                    [PSCustomObject]@{ id = 12; username = 'zz-test-pmorel'; firstname = 'Pascale'; lastname = 'Morel'; status = 7; state = 2; group_id = $null; manager_user_id = $null; role_ids = @(); custom_attributes = $null }
                )
                Roles      = @([PSCustomObject]@{ id = 30; name = 'ZZ-TEST-All Staff'; users = @(10); apps = @(40) })
                Groups     = @([PSCustomObject]@{ id = 20; name = 'ZZ-TEST-Seattle HQ'; MemberIds = @('10') })
                Apps       = @([PSCustomObject]@{ id = 40; name = 'ZZ-TEST-Wiki SAML'; connector_id = 110016; visible = $true })
                Mappings   = @([PSCustomObject]@{ id = 50; name = 'ZZ-TEST-Finance'; enabled = $true; conditions = @(1, 2); actions = @(1) })
            }
            Mock Get-OneLoginSeededObject { @($script:Fixture[$Type]) }
            Mock Invoke-OneLoginRequest { throw "Unexpected request $Method $Path" }
        }
    }

    It 'returns the shared report shape with -PassThru, and nothing without it' {
        InModuleScope TestEnvironment {
            (Get-OneLoginEnvironmentReport) | Should-BeNull
            $report = Get-OneLoginEnvironmentReport -PassThru
            $report.PSObject.TypeNames[0] | Should-Be 'OneLoginEnvironmentReport'
            $report.Provider | Should-Be 'OneLogin'
            $report.Target | Should-Be 'contoso'
            @($report.Sections) | Should-BeCollection @('Attributes', 'Users', 'Roles', 'Groups', 'Apps', 'Mappings', 'Policies', 'ApiAuthorizations', 'AppRules', 'Hooks', 'SelfRegistration')
            $report.Counts.Users | Should-Be 3
            $report.UsersByStatus.Suspended | Should-Be 1
            $report.UsersByState.Rejected | Should-Be 1
            $report.UsersWithManager | Should-Be 1
            $report.UsersInNoGroup | Should-Be 2
            ($report.Users | Where-Object Username -eq 'zz-test-mbell').Manager | Should-Be 'zz-test-jnino'
            ($report.Apps | Where-Object Name -eq 'ZZ-TEST-Wiki SAML').Connector | Should-Be 'SAML'
            ($report.Apps | Where-Object Name -eq 'ZZ-TEST-Wiki SAML').Roles | Should-Be 1
        }
    }

    It 'writes a file format as UTF-8 through the shared writer and requires a path for one' {
        InModuleScope TestEnvironment {
            { Get-OneLoginEnvironmentReport -OutputFormat CSV } | Should-Throw -ExceptionMessage '*-OutputPath*'
            $folder = Join-Path $TestDrive 'csv'
            Get-OneLoginEnvironmentReport -OutputFormat CSV -OutputPath $folder
            @(Get-ChildItem $folder -Filter 'OneLoginLab*.csv').Count | Should-Be 11
            $read = (Import-Csv (Join-Path $folder 'OneLoginLabUsers.csv') -Encoding UTF8 | Where-Object Username -eq 'zz-test-jnino').FirstName
            [string]::Equals($read, ('Jos' + [string][char]0xE9), [StringComparison]::Ordinal) | Should-BeTrue
        }
    }

    It 'keys each person by the username without the prefix, keeps the name as parts, and calls suspended and rejected disabled' {
        InModuleScope TestEnvironment {
            $snapshot = Get-OneLoginIdentitySnapshot
            $snapshot.Provider | Should-Be 'OneLogin'
            $snapshot.Target | Should-Be 'contoso'
            @($snapshot.Identities | ForEach-Object Key) | Should-BeCollection @('jnino', 'mbell', 'pmorel')
            @($snapshot.Identities | ForEach-Object Enabled) | Should-BeCollection @($true, $false, $false)
            $snapshot.Identities[0].DisplayName | Should-BeNull
            $snapshot.Identities[0].Surname | Should-Be 'Nino'
        }
    }
}
