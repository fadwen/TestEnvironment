# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The manifest declares 1.0.0. This section becomes `[1.0.0]` with a date when the first tag is
pushed and the release workflow publishes it.

### Added

- An interactive Entra session can now be a complete way to run, not only a way to bootstrap
  the service app. `Connect-TestEnvironment -Provider Entra -Interactive -FullAccess` asks for
  the delegated form of every permission the service app is granted, derived from the same CSV,
  so the first sign-in shows one consent screen and the session can then seed and tear down as
  the signed-in person. A tenant owner who does not want an application registration left
  behind never has to create one. Without the switch, `-Interactive` asks for nothing beyond
  what the client is already consented for, which is all a bootstrap needs; `-Scope` names an
  explicit list.
- **Authentik provider.** About five hundred objects across seventeen types on any Authentik
  instance: 98 groups and 306 users in the two tiers the Entra provider uses, a hand-designed
  core of edge cases and the AD provider's directory mapped across as the bulk, so the same
  people exist in three labs and `-Tier Core` is the fast loop. The core groups nest three
  deep and the bulk carries AD's own nesting, including groups with more than one parent;
  users of every type sit under a path of their own with free-form lab attributes;
  applications run over OAuth2 and proxy providers plus one with no provider and one hidden;
  expression policies bind to applications with one binding disabled; and notification rules
  deliver to webhook transports. `Tools\New-AuthentikTestSeedData.ps1` regenerates the bulk
  deterministically and a test fails if the committed files drift from what it writes.
  Above the directory: three RBAC roles with view and password-reset permissions, assigned
  through groups with one held by nobody; three OAuth2 scope mappings that turn the lab
  attributes into claims, attached to the seeded providers without dropping the standard
  scopes; six application entitlements, one granted to nobody; policies of five types, with a
  password policy bound to nothing and an event matcher bound to a notification rule; eleven
  bindings that grant access by group and by user directly, chosen so the mechanisms disagree
  with the expression policies on purpose; three user tokens covering never-expires, expiring
  and already-expired, with no secret ever read back, and three invitations, one of them
  reusable and one with a year to run. Teardown removes
  every layer in dependency order and proves ownership of each: entitlements by their
  application and the tag, tokens by the slug prefix and a seeded owner, invitations by the
  prefix and the tag in their fixed data. `New-AuthentikRole`, `New-AuthentikScopeMapping`,
  `New-AuthentikEntitlement`, `New-AuthentikBinding`, `New-AuthentikToken` and
  `New-AuthentikInvitation` are exported alongside the earlier five. The integration surface
  is complete too: a SAML provider whose responses are signed by a self-signed keypair the seed
  generates and owns, an LDAP provider and a RADIUS provider with a generated shared secret
  that never touches the CSV, and three outposts carrying the proxy, LDAP and RADIUS providers
  with no service connection, so nothing is deployed. `New-AuthentikOutpost` is exported;
  provider-specific settings ride in a Settings cell of the applications file. Teardown also
  removes the hidden per-user role Authentik creates for each outpost's service account and
  leaves behind when the outpost is deleted, so an instance returns to its exact baseline.
  Flows last: six stages and three flows built from them, a sign-in flow with an optional
  second factor attached to the SAML and proxy providers, an authorization flow with expiring
  consent on the expenses client, and an enrolment flow that only refuses, tied to the
  reusable invitation. A seeded flow never becomes anyone's default: `New-AuthentikFlow`
  never writes to the brand or to an unprefixed flow, a test pins it, and there is no switch
  to change it, the same shape as the Entra rule that a Conditional Access policy is never
  enforcing. `New-AuthentikFlow` is exported.
  Connects with an API token or the service account `New-TestServiceApp` creates, which is a
  superuser service account with a non-expiring token kept DPAPI-protected or in the
  SecretStore. Teardown proves ownership
  by the seed tag in attributes, the marker in an application's description, and a
  provider's attachment to a seeded application, and keeps the service account unless told
  otherwise. `New-AuthentikGroup`, `New-AuthentikUser`, `New-AuthentikApplication`,
  `New-AuthentikPolicy` and `New-AuthentikNotificationRule` are exported for rebuilding one
  type at a time.
- After an interactive Entra sign-in, `Connect-TestEnvironment` reports whether the tenant
  already holds a bootstrapped service app and whether this machine has its credential, and
  prints the exact next command for the case it found: connect app-only, create the app, or
  replace one whose key is elsewhere. A delegated token that cannot list applications is
  reported as unknown with both options rather than as "nothing yet".
- Command help is compiled. The Markdown under `docs/TestEnvironment/` is the source, built by
  `Build/Build-Help.ps1` with Microsoft.PowerShell.PlatyPS into `en-US/TestEnvironment-Help.xml`,
  which every exported command names through `.EXTERNALHELP`. `about_TestEnvironment` covers
  the concepts no single command owns: the provider model, the prefix and seed tag, the two
  safety properties with no parameter, teardown's ownership proof and the shared SecretStore.
  A CI gate fails on a placeholder, a missing or orphaned page, a lost keyword, or committed
  MAML that no longer matches the Markdown.

First release as a standalone module, split out of the private repository where it was
assembled. Before the split it was three separate modules - `ADTestEnvironment`,
`EntraTestEnvironment` and `OktaTestEnvironment` - each of which had its own SecretStore
handling, its own password generator and its own certificate persistence, converging on the
same lessons at its own pace. Those now live in `Core` once, and each directory keeps only what
genuinely differs about it under `Providers/`.

- `Connect-TestEnvironment` names the provider once. Everything after it -
  `New-TestEnvironment`, `Get-TestEnvironmentReport`, `Remove-TestEnvironment`,
  `Get-TestAccessToken`, `New-TestServiceApp`, `Get-TestServiceApp`,
  `Update-TestContainment` - reads the active connection and mirrors the provider command's
  own parameters, so tab completion and binding errors come from the real command.
- **Entra provider.** Roughly 1,150 objects held in administrative units: users, guests,
  groups with real nesting, devices, applications and service principals, named locations,
  directory extensions, authentication strengths, custom directory roles, PIM role
  eligibilities that are eligible and never active, and Conditional Access policies that are
  report-only or disabled and can never be made to enforce. Authenticates with a client
  assertion signed by in-box .NET types, so it needs no Graph SDK.
- **Active Directory provider.** Roughly 1,100 objects under `OU=TestData`, sharing its
  people with the Entra data so hybrid matching is testable. Stamps `adminDescription` on
  every object it creates and proves ownership before deleting anything. RSAT is imported at
  connect time rather than declared, so the module still imports where it is absent.
- **Okta provider.** About sixty objects across ten types inside a trial org's ten-user
  ceiling, seed-tagged through a custom profile attribute, with an OAuth service app
  bootstrapped once from an API token.
- `RequiredModules` is empty, and a contract test keeps it that way: the providers do not
  share a platform, and importing this module installs nothing.
- 1,234 Pester tests with every Graph call, RSAT cmdlet and Okta request mocked. The AD
  provider's suites bind against generated stubs under `Tests/Stubs`, appended to
  `PSModulePath`, so they run on a host without RSAT.

### Fixed

- `Remove-EntraEnvironment` judges what the identity can remove before it prompts for
  anything. A run confirmed the deletion of seven service principals one by one and watched
  each refused with a 403. The token's permissions and the identity's directory roles are now
  read up front; a layer the identity cannot delete is set aside with one warning and never
  reaches a prompt, and under `Application.ReadWrite.OwnedBy` the applications it does not
  own are set aside by reading their owners first. An identity whose rights cannot be read is
  allowed everything, and `-SkipPermissionCheck` attempts everything regardless.
- `Remove-EntraEnvironment` no longer stops at the first step that cannot enumerate its
  objects. A delegated token without `Policy.Read.All` was refused the authentication
  strengths with a 403, the exception escaped the whole teardown after the Conditional Access
  policies were already gone, and the tenant was left half torn down. Every step now records
  a read failure as a failure of its own, warns, and lets the steps after it run; the summary
  says what was not attempted. The role-eligibility step keeps its stricter rule and still
  refuses to delete role definitions it cannot prove unreferenced.

### Changed

- The README is split. The root now describes what every provider shares - the one
  connect-seed-report-teardown surface, the guarantees, installation, command help, tests and
  architecture - and lists the providers with a link to each. Everything specific to a
  directory lives in that provider's own page: `Providers/Entra/README.md`,
  `Providers/AD/README.md`, `Providers/Okta/README.md` and `Providers/Authentik/README.md`. The
  provider pages ship with the module, since `Providers/` is staged whole.
- Credential records now live under `~/.testenvironment`. Records written by the three earlier
  modules under their own folders are still read when no newer record exists, so nothing
  needs re-bootstrapping.
- The per-user SecretStore is opened with this module's default password first, then with
  each of the three defaults the earlier modules used, because one machine has one store
  shared by everything that has ever configured it.

### Compatibility

The three earlier modules survive as compatibility shims in the repository this one was split
from. Each forwards every name it used to export to an installed copy of this module, so
scripts written against `Connect-EntraTestEnvironment` or `New-OktaTestUser` keep working.
