# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The manifest declares 1.0.0. This section becomes `[1.0.0]` with a date when the first tag is
pushed and the release workflow publishes it.

### Added

- **FreeIPA provider, DNS.** The seeded hosts resolve. The seed keeps its own zones - a forward
  zone `<prefix>lab.<domain>` that every seeded host now lives in, and a reverse zone for
  10.213.0.0/16 - and never writes into the realm's zone. Every host but the orphan carries an
  address, one /24 per office, which FreeIPA turns into an A and a PTR record on creation;
  eleven records go in around them: aliases, a mail exchanger and a text record at the apex, a
  service record, and the shapes a review has to notice - an address with no host, an alias with
  no target, a reverse record with no forward name, one name with two addresses. Ownership is
  the SOA contact both zones carry, which the server can filter on; a zone of the seed's name
  with another contact is refused, never adopted. Teardown deletes the zones whole after the
  hosts. A realm without DNS is a warning, and the hosts are created without addresses.
  `New-FreeIPADnsZone` is exported; the host name a seeded object carries changes from
  `zz-test-web01.<domain>` to `zz-test-web01.zz-test-lab.<domain>`.
- **FreeIPA provider, certificates.** Every certificate the seed shows is a real one from the
  realm's own CA: four CA ACLs, one of which is what lets a user certificate be issued at all,
  one a paused pilot that is disabled, one scoped beside the stock rule, one granted to nobody;
  ten certificates issued against requests built with in-box .NET and a throwaway key, six on
  users, three on services and one on a host, each added to its entry, with one revoked for key
  compromise beside its replacement on the same user, one on certificate hold, one service
  certificate revoked as ceased, and a valid one on the disabled account; and a third mapping
  rule that maps the realm CA's certificates back to their users by the certificate itself.
  Ownership of a certificate is its owner: the CA is asked for the certificates the seeded
  users, services and hosts hold, never for a subject pattern. Teardown revokes what is still
  valid, by the hex serial the CA returns, because a CA has no delete and Windows PowerShell
  cannot hold the decimal serial exactly. The stock CA ACL and the shipped profiles join the
  list of objects the seed never names. `New-FreeIPACaAcl` and `New-FreeIPACertificate` are
  exported, eighteen steps and twenty-four seed files.
- **FreeIPA provider, the identity detail.** The last layer: two ID views, one applied to the
  legacy host with a user renamed and given a different UID, shell and home, a second user's
  shell alone, and a group renamed with a new GID, and one applied to nothing; four OTP tokens
  enrolled on their users by the administrator, one disabled, one expired, with the secret the
  realm mints never read back; five automember rules that agree with the memberships the data
  already lists, with the seeded users and hosts rebuilt against them by name and never the
  realm at large; an automount location with two indirect maps and three keys pointing at the
  seeded NFS host under the realm's domain; three SELinux user maps, one scoped by an HBAC
  rule and one disabled; and two certificate mapping rules, one matched by the certificate
  data a seeded user carries. Teardown unapplies a view from its hosts before deleting it and
  removes the rest in reverse; the report shows each view's hosts and overrides, each token's
  expiry, and every automount key. The Default Trust View, the default automount location and
  the automember default groups join the list of objects the seed never names.
  `New-FreeIPAIdView`, `New-FreeIPAOtpToken`, `New-FreeIPAAutomemberRule`,
  `New-FreeIPAAutomount`, `New-FreeIPASelinuxUserMap` and `New-FreeIPACertMapRule` are exported,
  which completes the provider at twenty-two seed files and sixteen steps.
- **FreeIPA provider, the access layers.** Over the directory: four netgroups, one built from a
  group and two host groups and one that contains only other netgroups; three custom HBAC
  services and three service groups, and seven HBAC rules including an allow-everything rule
  that is switched off, a rule bound to nothing, a user admitted twice by name and by group, and
  a disabled user still named; eight sudo commands and four command groups, and seven sudo
  rules including an editor granted to contractors without a password, a run-as of a local
  account FreeIPA stores as external, a disabled rule for a disabled user, and an allow and a
  deny in one rule; three permissions, the one that writes scoped by the seed tag, three
  privileges and four roles, one held by a host and one by nobody; three password policies at
  three priorities, one that never expires a password; and four Kerberos services on seeded
  hosts with constrained delegation between two of them. A stock PAM service or privilege may
  be a member of a seeded rule or role and is never changed; a sudo command that already exists
  in the realm is reused and left behind; and no request ever names a rule the realm shipped
  with, which is the FreeIPA analogue of the two safety properties with no parameter. Teardown
  removes every layer in the reverse order and the report describes them all, with a category
  of all shown as the clause it is. `New-FreeIPANetgroup`, `New-FreeIPAHbacRule`,
  `New-FreeIPASudoRule`, `New-FreeIPARole`, `New-FreeIPAPasswordPolicy` and
  `New-FreeIPAService` are exported.
- **FreeIPA provider, the directory layer.** Connects to a realm over its JSON-RPC API with an
  administrator's credential or the service account `New-TestServiceApp` creates: a user with
  no shell in the admins group, whose password is made current as the user (FreeIPA expires
  every password an administrator sets on the spot), pushed ten years out so the realm's
  policy cannot expire it under a run, and kept DPAPI-protected or in the SecretStore. The
  realm's own certificate authority is pinned from a PEM at connect time and carried in the
  record, so a server certificate from that CA is trusted without touching the machine's
  store; the pinning runs in a small compiled validator because a PowerShell callback handed
  to the HTTP client runs on a thread with no runspace. Seeds the directory layer of the
  data: 102 groups nested through membership as POSIX, non-POSIX and external, 333 users
  across FreeIPA's four lifecycle states with the preserved one placed before it is preserved
  so the preservation strips something, 30 host groups and 413 hosts as forced records that
  never touch DNS or a keytab, each in a host group for its kind and one for its office.
  Every object carries the tag in `userclass` or the marker in its description, and teardown
  finds them by exactly that, deleting in batches of fifty while still confirming every one
  by name. Verified against a FreeIPA 4.13 realm: the full seed in eleven minutes, the report
  reading back every designed state, and teardown returning the realm to its baseline.
  `New-FreeIPAGroup`, `New-FreeIPAUser`, `New-FreeIPAHostgroup` and `New-FreeIPAHost` are
  exported. The credential-protection helpers the Authentik provider had - DPAPI at rest, the
  record and its folder restricted to the current user - moved to `Core` as
  `Protect-TestSecret`, `Unprotect-TestSecret` and `Protect-TestFile`, and both providers use
  them.
- **FreeIPA provider, seed data.** The provider folder, its seed data and the tool that
  generates the bulk tier. About 950 objects across twenty-two files: users in all four
  lifecycle states, POSIX, non-POSIX and external groups, hosts and host groups, netgroups,
  HBAC services and rules, sudo commands and rules, permissions, privileges and roles, password
  policies, service principals, ID views and overrides, OTP tokens, automember rules, an
  automount location, SELinux user maps, certificate mapping rules and service delegation.
  The users, groups, hosts and host groups are the AD provider's directory mapped across at
  parity, so the same people and machines exist in every lab. A seed data suite pins the
  shapes and every reference between files, and that no row names an object FreeIPA created at
  install. `Connect-TestEnvironment` lists `FreeIPA`; connecting, seeding, reporting and
  teardown follow in later changes.
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
  provider-specific settings ride in a Settings cell of the applications file. Every provider
  is created with the property mappings the admin UI would have selected for it, since the API
  attaches none and a provider without them cannot be signed in through. Teardown also
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

- `Providers\Entra\Tools\New-EntraTestSeedData.ps1` reads the AD provider's seed data from this
  repository by default rather than from a sibling checkout of the module it was split from. The
  output is byte-identical.
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
