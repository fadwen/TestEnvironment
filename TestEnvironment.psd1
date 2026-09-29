@{
    # Module manifest for TestEnvironment
    RootModule = 'TestEnvironment.psm1'
    ModuleVersion = '1.5.0'
    GUID = 'c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'Jeffrey Stuhr'
    Copyright = '(c) 2026 Jeffrey Stuhr. All rights reserved.'
    Description = 'Seeds a realistic identity test environment in Entra ID, Active Directory, Okta, Authentik, FreeIPA, PingOne or OneLogin - users in every lifecycle state, groups, devices and hosts, and the access policy over them - and tears it down again cleanly, proving ownership of every object before deleting it. One connect-seed-report-teardown surface for all seven, no module dependencies, Windows PowerShell 5.1 and PowerShell 7.'

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
        'Test-TestEnvironment',
        'Compare-TestEnvironment',
        'Repair-TestEnvironment',
        'Get-TestEnvironmentRuntime',
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
        'New-ADTestDnsZone',
        'New-ADTestPasswordPolicy',
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
        'New-FreeIPAIdentityProvider',

        # PingOne provider components
        'New-PingOneProfileAttribute',
        'New-PingOnePopulation',
        'New-PingOneUser',
        'New-PingOneGroup',
        'New-PingOneResource',
        'New-PingOneApplication',

        # OneLogin provider components
        'New-OneLoginCustomAttribute',
        'New-OneLoginRole',
        'New-OneLoginGroup',
        'New-OneLoginApp',
        'New-OneLoginMapping',
        'New-OneLoginUser',
        'New-OneLoginPolicy',
        'New-OneLoginAppRule',
        'New-OneLoginApiAuthorization',
        'New-OneLoginSmartHook',
        'New-OneLoginSelfRegistration',
        'New-OneLoginMfaFactor',
        'Get-OneLoginAppCredential'
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
                'Entra', 'EntraID', 'AzureAD', 'MicrosoftGraph', 'ActiveDirectory', 'Okta', 'Authentik', 'FreeIPA', 'PingOne', 'OneLogin',
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
            # The current release only. The Gallery refuses ReleaseNotes over 10600 characters, and
            # 1.5.0 was rejected for carrying every release since 1.0.0; the history is in CHANGELOG.md.
            ReleaseNotes = @'
1.5.0 - A seventh provider: OneLogin.

OneLogin joins Entra ID, Active Directory, Okta, Authentik, FreeIPA and PingOne. It seeds one
account through the OneLogin API as an API credential: four custom user fields, 321 people in
every lifecycle state OneLogin keeps - one of them locked - with managers and the directory
identifiers a synchronised account carries, four roles, five office groups, two security policies,
five OIDC and SAML apps with two app rules, two API authorization servers with scopes, claims and
seeded clients, two user mappings, a disabled Smart Hook, a disabled self-registration profile and
MFA factors where the account offers them. It reports, verifies, repairs and tears down like every
other provider, and the shared people carry exactly the shared names.

It is built to run in an account real people sign in to. Most OneLogin objects carry nothing but
a name, so each is proved by what it holds or names: a role or group by holding seeded people and
nothing else, a policy by its seeded groups, a mapping by a seed-tag condition it always carries,
an app rule by its seeded app, a hook by a marker line in its code. Nothing seeded can reach a
real object and nothing real is drawn in: a mapping acts on seeded people only, the hook and the
sign-up page are always off, a policy is never the default, only seeded apps are API clients, no
MFA factor is switched on for the account, and every directory identifier is under the prefix or
the lab domain. None of that has a parameter.

An app's client secret is dropped by default. New-TestEnvironment -SaveAppSecret keeps the two
confidential apps' secrets through the shared credential record writer, DPAPI or the SecretStore;
Get-OneLoginAppCredential returns them as credentials, and teardown deletes each with its app and
any whose app is gone, so they do not build up.

Thirteen new exported commands. Verified live against a OneLogin trial on Windows PowerShell 5.1
and PowerShell 7: every verification check passing and a teardown that left nothing behind.

Every earlier release, and this one in full, is in the changelog:
https://github.com/fadwen/TestEnvironment/blob/main/CHANGELOG.md
'@
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfoURI is omitted for the same reason as IconUri, and because there is nothing to
    # point it at: help is comment-based on each function, not updatable help served over
    # the wire.
}
