@{
    # Module manifest for TestEnvironment
    RootModule = 'TestEnvironment.psm1'
    ModuleVersion = '1.2.0'
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
        'New-PingOneApplication'
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
1.2.0 - Seed data that can find string bugs, and four defects the live runs turned up.

Every provider's people were accented Latin and nothing else, so the only string bugs this
module could find were the ones Latin-1 exposes. Nine new people each carry one specific way
that string handling goes wrong: Han with an ideographic space that is not U+0020, a surname
above the basic plane where one character is two UTF-16 units, Cyrillic homoglyphs a duplicate
check made by eye cannot see, Greek with its positional final sigma, right-to-left Arabic, a
decomposed name that renders identically to an existing precomposed one, a Turkish dotless i,
an eszett that upper-cases into two characters, and Devanagari combining vowel signs. Every
login stays plain ASCII, because that is the field a directory actually constrains; the writing
system lives in the display name, where a real directory keeps it. Counts move with it: Active
Directory 296 users to 311, Entra 305 to 329, Authentik 306 to 330, FreeIPA 333 to 357.

Okta is capped at eight users by its licence and cannot carry the cohort, so its one Japanese
person is now written in kanji rather than romaji, as she is in every other provider.

Fixes, all found while verifying that data against live directories:

- An Active Directory teardown refused at the confirmation prompt deleted the environment
  anyway. The guard returned from begin{}, which ends the begin block and nothing else, so
  process{} ran regardless. Unattended it always took that path, because Read-Host reads EOF
  and never matches CONFIRM. An automated teardown must now pass -Force, which was always the
  documented bypass; -WhatIf still beats it.
- The seeding counters undercounted badly - 176 of 311 users and 569 of 688 devices, with none
  skipped and no error raised - because jobs that finished between two readings of the job list
  were dropped from tracking without ever being received.
- Entra teardown left behind any user still in a role-assignable group, which Graph refuses to
  delete until the group is gone, and the group deletion needs a moment to take effect. That
  refusal is now retried once after a pause.
- Service account creation failed at random, about one seed run in three hundred, when a
  generated password happened to contain a three-letter token of the account's own display
  name. Windows reports that as a length, complexity or history failure and names none of the
  three. A refused account was also left behind without a password, which every later run then
  skipped as already created.

1.1.0 - The Active Directory provider catches up, and learns to survive a messy domain.

Seeded computers now resolve: two directory-integrated DNS zones of the seed's own, an A
record and a PTR for all 688 devices, and records around them that deliberately do not
reconcile. Eight service accounts register a principal name against a seeded server and one
delegates, constrained; unconstrained delegation is never seeded. Three fine-grained password
policies sit over seeded groups at three precedences. Remove-TestEnvironment -Keep now works
against Active Directory, which was the only provider without it.

Connecting picks a domain controller that answers rather than trusting discovery, and pins
every later call to it, so a domain that registers a controller it is not running no longer
breaks a seed halfway through. If that controller stops answering mid-run the seed stops with
one message instead of failing every remaining step.

Fixes: teardown claimed password settings objects by name pattern rather than by the seed tag;
the service account step discarded the password export entries it built, so the documentation
wrote nothing and the entries leaked onto the output stream; DNS zone objects were looked for
in the wrong directory partition, so the seed tag was never written and teardown refused to
remove its own zones.

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
