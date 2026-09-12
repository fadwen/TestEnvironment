@{
    # Module manifest for TestEnvironment
    RootModule = 'TestEnvironment.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'Jeffrey Stuhr'
    Copyright = '(c) 2026 Jeffrey Stuhr. All rights reserved.'
    Description = 'Seeds a realistic identity test environment in Entra ID, Active Directory, Okta, Authentik or FreeIPA - users in every lifecycle state, groups, devices and hosts, and the access policy over them - and tears it down again cleanly, proving ownership of every object before deleting it. One connect-seed-report-teardown surface for all five, no module dependencies, Windows PowerShell 5.1 and PowerShell 7.'

    # PowerShell Version Requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required Modules
    # Deliberately none, and a contract test enforces it. Importing this module must install
    # nothing and require nothing, because the providers do not share a platform: the Entra and
    # Okta providers reach a REST API from any host, while the AD provider needs RSAT's
    # ActiveDirectory and GroupPolicy modules. Declaring those here would impose a Windows-only,
    # RSAT-only dependency on somebody who only wanted to seed an Okta org from a container. The
    # AD provider therefore imports them lazily, at connect time, and says so clearly if they
    # are absent.
    RequiredModules = @()

    # Functions to Export
    FunctionsToExport = @(
        # Shared, provider-agnostic
        'Connect-TestEnvironment',
        'Disconnect-TestEnvironment',
        'Get-TestEnvironmentProvider',
        'New-TestEnvironment',
        'Remove-TestEnvironment',
        'Get-TestEnvironmentReport',
        'Get-TestAccessToken',
        'New-TestServiceApp',
        'Get-TestServiceApp',
        'Update-TestContainment',

        # Entra provider components, named honestly. An administrative unit is not an OU and a
        # Conditional Access policy is not an Okta sign-on policy, so hiding them behind a
        # shared noun would be a worse abstraction than letting them keep their own.
        'New-EntraAdministrativeUnit',
        'New-EntraUser',
        'New-EntraGuestUser',
        'New-EntraGroup',
        'New-EntraDevice',
        'New-EntraApplication',
        'New-EntraNamedLocation',
        'New-EntraConditionalAccessPolicy',
        'New-EntraAuthenticationStrength',
        'New-EntraDirectoryRole',
        'New-EntraRoleEligibility',
        'New-EntraDirectoryExtension',
        'Set-EntraLicense',

        # Active Directory provider components. These keep a Test infix where the Entra
        # ones did not, and the reason is collision rather than taste: New-ADUser,
        # New-ADGroup, New-ADComputer and Get-ADDomain are real cmdlets from the RSAT
        # module this provider imports. A function of the same name would be found ahead
        # of the cmdlet for everything else in the session, which is a far worse outcome
        # than an inconsistent noun.
        'New-ADTestOUStructure',
        'New-ADTestUser',
        'New-ADTestDevice',
        'New-ADTestSecurityGroups',
        'New-ADTestServiceAccount',
        'New-ADTestEdgeCase',
        'New-ADTestGroupPolicy',
        'Get-ADTestPasswordFromVault',

        # Okta provider components. These drop the Test infix as the Entra ones did, because
        # Okta ships no PowerShell cmdlets of its own for them to collide with.
        'New-OktaProfileAttribute',
        'New-OktaUser',
        'New-OktaGroup',
        'New-OktaGroupRule',
        'New-OktaApp',
        'New-OktaUserType',
        'New-OktaNetworkZone',
        'New-OktaPolicy',
        'New-OktaLinkedObject',
        'New-OktaTrustedOrigin',
        'New-OktaEventHook',
        'New-AuthentikGroup',
        'New-AuthentikUser',
        'New-AuthentikRole',
        'New-AuthentikApplication',
        'New-AuthentikOutpost',
        'New-AuthentikFlow',
        'New-AuthentikScopeMapping',
        'New-AuthentikEntitlement',
        'New-AuthentikPolicy',
        'New-AuthentikNotificationRule',
        'New-AuthentikBinding',
        'New-AuthentikToken',
        'New-AuthentikInvitation',

        # FreeIPA provider components. No Test infix, for the same reason as Entra and Okta.
        'New-FreeIPAGroup',
        'New-FreeIPAUser',
        'New-FreeIPAHostgroup',
        'New-FreeIPAHost',
        'New-FreeIPANetgroup',
        'New-FreeIPAHbacRule',
        'New-FreeIPASudoRule',
        'New-FreeIPARole',
        'New-FreeIPAPasswordPolicy',
        'New-FreeIPAService',
        'New-FreeIPAIdView',
        'New-FreeIPAOtpToken',
        'New-FreeIPAAutomemberRule',
        'New-FreeIPAAutomount',
        'New-FreeIPASelinuxUserMap',
        'New-FreeIPACertMapRule',
        'New-FreeIPACaAcl',
        'New-FreeIPACertificate',
        'New-FreeIPADnsZone',
        'New-FreeIPAIdentityProvider'
    )

    # Cmdlets to Export
    CmdletsToExport = @()

    # Variables to Export
    VariablesToExport = @()

    # Aliases to Export
    AliasesToExport = @()

    # Private Data
    PrivateData = @{
        PSData = @{
            Tags = @(
                'TestData', 'TestEnvironment', 'SeedData', 'Identity', 'IAM', 'IdentityManagement',
                'Entra', 'EntraID', 'AzureAD', 'MicrosoftGraph', 'ActiveDirectory', 'Okta', 'Authentik', 'FreeIPA',
                'Kerberos', 'LDAP', 'ConditionalAccess', 'PIM', 'HBAC', 'Sudo',
                'Automation', 'Pester', 'Lab',
                'PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS'
            )
            LicenseUri = 'https://github.com/fadwen/TestEnvironment/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/TestEnvironment'

            # IconUri is omitted rather than set to ''. An empty string is not "no icon":
            # the nuspec writer emits an empty <iconUrl> element and NuGet rejects the pack
            # with 'IconUrl cannot be empty', so Publish-PSResource fails before it ever
            # reaches the Gallery. The same applies to HelpInfoURI below.
            ReleaseNotes = @'
1.0.0 - First release.

Five providers behind one connect-seed-report-teardown surface:

- Entra ID: ~1,150 objects across twelve types, held in administrative units.
- Active Directory: ~1,100 objects across five types, held in OU=TestData.
- Okta: ~60 objects across ten types, seed-tagged.
- Authentik: ~480 objects across seventeen types, under a user path of their own.
- FreeIPA: ~970 objects across twenty-eight types, seed-tagged, in DNS zones of their own.

The Entra and Active Directory providers seed the same people, so hybrid identity matching
is testable across the two.

Every provider proves ownership before deleting anything, never puts a directory into an
enforcing state (a seeded Conditional Access policy is report-only, a seeded PIM eligibility
is never active, a stock FreeIPA rule is never touched, and none of that is a parameter),
and honours -WhatIf over -Force on every destructive command. RequiredModules is empty:
importing this module installs nothing. The AD provider imports RSAT at connect time; the
other four run from a stock host on any platform.

See CHANGELOG.md for the detail.
'@
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfoURI is omitted for the same reason as IconUri, and because there is nothing to
    # point it at: help is comment-based on each function, not updatable help served over
    # the wire.
}
