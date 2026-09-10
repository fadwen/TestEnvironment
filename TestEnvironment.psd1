@{
    # Module manifest for TestEnvironment
    RootModule = 'TestEnvironment.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'EntraVantage LLC'
    Copyright = '(c) 2026 EntraVantage LLC. All rights reserved.'
    Description = 'Seeds and tears down realistic identity test environments across several providers, sharing one implementation of the concerns they have in common'

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
        'New-AuthentikInvitation'
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
            Tags = @('TestData', 'Identity', 'Entra', 'EntraID', 'ActiveDirectory', 'Okta', 'Authentik', 'Automation', 'Graph')
            LicenseUri = 'https://github.com/fadwen/TestEnvironment/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/TestEnvironment'

            # IconUri is omitted rather than set to ''. An empty string is not "no icon":
            # the nuspec writer emits an empty <iconUrl> element and NuGet rejects the pack
            # with 'IconUrl cannot be empty', so Publish-PSResource fails before it ever
            # reaches the Gallery. The same applies to HelpInfoURI below.
            ReleaseNotes = @'
1.0.0 - First release as a standalone module.

Three providers - Entra ID, Active Directory and Okta - behind one connect-seed-report-teardown
surface, with the concerns they share implemented once in Core. RequiredModules is empty:
importing this module installs nothing, the AD provider imports RSAT at connect time, and the
Entra and Okta providers run from any host.

See CHANGELOG.md for what the consolidation changed and for the compatibility shims that keep
the three earlier modules' names working.
'@
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfoURI is omitted for the same reason as IconUri, and because there is nothing to
    # point it at: help is comment-based on each function, not updatable help served over
    # the wire.
}
