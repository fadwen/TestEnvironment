#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The six snapshot readers behind Compare-TestEnvironment, in one suite because what they share
    is the point: each reads the users the way teardown finds them and reduces them to the same
    identity, with the key stripped of whatever that provider added - the seed prefix on a PingOne
    username, the suffix on an Entra UPN, the domain on an Okta login - so the same person carries
    the same key everywhere the shared logins are kept. PingOne leaves the display name absent
    rather than composing one; FreeIPA reads the lock flag as the inverse of enabled; Entra leaves
    guests out; Okta calls only ACTIVE enabled.

    Everything is mocked. No directory is reached.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}

Describe 'The identity snapshots' -Tag 'Unit', 'Private' {

    It 'PingOne strips the seed prefix from the username and keeps the name as parts only' {
        InModuleScope TestEnvironment {
            Mock Get-PingOneConnection { @{ EnvironmentId = 'env-1'; Prefix = 'ZZ-TEST-' } }
            Mock Get-PingOneSeededObject { @([PSCustomObject]@{ id = 'u1'; username = 'zz-test-jnino'; name = [PSCustomObject]@{ given = 'José'; family = 'Niño' }; enabled = $false }) }
            $snapshot = Get-PingOneIdentitySnapshot
            $snapshot.Provider | Should-Be 'PingOne'
            $snapshot.Target | Should-Be 'env-1'
            $snapshot.Identities[0].Key | Should-Be 'jnino'
            $snapshot.Identities[0].Login | Should-Be 'zz-test-jnino'
            $snapshot.Identities[0].DisplayName | Should-BeNull
            $snapshot.Identities[0].GivenName | Should-Be 'José'
            $snapshot.Identities[0].Enabled | Should-BeFalse
            Should-Invoke Get-PingOneSeededObject -Times 1 -Exactly -ParameterFilter { $Type -eq 'Users' }
        }
    }

    It 'Entra strips the prefix and suffix from the UPN and leaves guests out' {
        InModuleScope TestEnvironment {
            Mock Get-EntraConnection { @{ TenantId = 'tenant-1'; UpnSuffix = 'lab.example.com' } }
            Mock Get-EntraSeedMarker { [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; UpnSuffix = 'lab.example.com' } }
            Mock Get-EntraSeededObject { @(
                    [PSCustomObject]@{ id = 'u1'; userPrincipalName = 'ZZ-TEST-JNino@lab.example.com'; displayName = 'José Niño'; givenName = 'José'; surname = 'Niño'; accountEnabled = $true; userType = 'Member' }
                    [PSCustomObject]@{ id = 'g1'; userPrincipalName = 'guest_example.com#EXT#@lab.example.com'; displayName = 'Guest'; accountEnabled = $true; userType = 'Guest' }
                ) }
            $snapshot = Get-EntraIdentitySnapshot
            @($snapshot.Identities).Count | Should-Be 1
            $snapshot.Identities[0].Key | Should-Be 'jnino'
            $snapshot.Identities[0].DisplayName | Should-Be 'José Niño'
            $snapshot.Identities[0].Surname | Should-Be 'Niño'
            $snapshot.Target | Should-Be 'tenant-1'
        }
    }

    It 'Okta keys by the local part of the login and calls only ACTIVE enabled' {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection { @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'; EmailDomain = 'oktalab.example.com' } }
            Mock Get-OktaSeededUser { @(
                    [PSCustomObject]@{ id = 'u1'; status = 'ACTIVE'; profile = [PSCustomObject]@{ login = 'jnino@oktalab.example.com'; displayName = 'José Niño'; firstName = 'José'; lastName = 'Niño' } }
                    [PSCustomObject]@{ id = 'u2'; status = 'SUSPENDED'; profile = [PSCustomObject]@{ login = 'mbell@oktalab.example.com'; displayName = 'Marcus Bell'; firstName = 'Marcus'; lastName = 'Bell' } }
                ) }
            $snapshot = Get-OktaIdentitySnapshot
            @($snapshot.Identities | ForEach-Object { $_.Key }) | Should-BeCollection @('jnino', 'mbell')
            @($snapshot.Identities | ForEach-Object { $_.Enabled }) | Should-BeCollection @($true, $false)
            $snapshot.Identities[0].Surname | Should-Be 'Niño'
        }
    }

    It 'Authentik keys by the username and keeps the one name field as the display name' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection { @{ BaseUrl = 'https://auth.example.com'; Prefix = 'ZZ-TEST-' } }
            Mock Get-AuthentikSeededObject { @([PSCustomObject]@{ pk = 1; username = 'jnino'; name = 'José Niño'; is_active = $true }) }
            $snapshot = Get-AuthentikIdentitySnapshot
            $snapshot.Identities[0].Key | Should-Be 'jnino'
            $snapshot.Identities[0].DisplayName | Should-Be 'José Niño'
            $snapshot.Identities[0].GivenName | Should-BeNull
            $snapshot.Target | Should-Be 'https://auth.example.com'
        }
    }

    It 'FreeIPA reads the detail, unwraps the lists, and reads the lock flag as the inverse of enabled' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-' } }
            Mock Get-FreeIPASeededObject { @(
                    [PSCustomObject]@{ uid = @('jnino'); displayname = @('José Niño'); givenname = @('José'); sn = @('Niño'); nsaccountlock = $false }
                    [PSCustomObject]@{ uid = @('talvarez'); displayname = @('Tomás Álvarez'); givenname = @('Tomás'); sn = @('Álvarez'); nsaccountlock = $true }
                ) }
            $snapshot = Get-FreeIPAIdentitySnapshot
            @($snapshot.Identities | ForEach-Object { $_.Key }) | Should-BeCollection @('jnino', 'talvarez')
            @($snapshot.Identities | ForEach-Object { $_.Enabled }) | Should-BeCollection @($true, $false)
            $snapshot.Identities[0].DisplayName | Should-Be 'José Niño'
            Should-Invoke Get-FreeIPASeededObject -Times 1 -Exactly -ParameterFilter { $Type -eq 'Users' -and $Detail }
        }
    }

    It 'AD keys by the SAM account name, reads only the tagged users under the seed OU, and reads none when the OU is gone' {
        InModuleScope TestEnvironment {
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
            Mock Get-ADTestSeedMarker { [PSCustomObject]@{ Prefix = 'ZZ-TEST-'; Tag = 'ZZ-TEST-seed' } }
            Mock Get-ADOrganizationalUnit { @([PSCustomObject]@{ Name = 'ZZ-TEST-TestData' }) }
            Mock Get-ADUser { @(
                    [PSCustomObject]@{ SamAccountName = 'JoseN'; DisplayName = 'José Niño'; GivenName = 'José'; Surname = 'Niño'; Enabled = $true; adminDescription = 'ZZ-TEST-seed' }
                    [PSCustomObject]@{ SamAccountName = 'intruder'; DisplayName = 'Not Ours'; Enabled = $true; adminDescription = $null }
                ) }
            $snapshot = Get-ADIdentitySnapshot -WarningAction SilentlyContinue
            @($snapshot.Identities | ForEach-Object { $_.Key }) | Should-BeCollection @('josen')
            $snapshot.Target | Should-Be 'contoso.com'
            Should-Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter { $SearchBase -eq 'OU=Users,OU=ZZ-TEST-TestData,DC=contoso,DC=com' }

            Mock Get-ADOrganizationalUnit { @() }
            @((Get-ADIdentitySnapshot).Identities) | Should-BeCollection -Count 0
        }
    }
}
