# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [1.2.0] - 2026-09-12

### Added

- **Seed data covering writing systems beyond the Latin alphabet.** Every provider's people were
  accented Latin and nothing else, so the only string bugs the seed could find were the ones
  Latin-1 exposes. Nine new people now carry Han with an ideographic space that is not U+0020, a
  surname above the basic plane where one character is two UTF-16 units, Cyrillic homoglyphs a
  duplicate check made by eye cannot see, Greek with its positional final sigma, right-to-left
  Arabic, a decomposed name that renders identically to an existing precomposed one, a Turkish
  dotless i, an eszett that upper-cases into two characters, and Devanagari combining vowel
  signs. They are hand-designed core rows in the Entra, Authentik and FreeIPA providers and real
  people in the Active Directory directory, with six more in AD alone so the same writing systems
  appear at bulk volume in every provider that maps from it. Every login stays plain ASCII: the
  key becomes a mailNickname, a userPrincipalName, a POSIX username or an API path, and the
  script belongs in the display name, which is where a real directory keeps it. Okta is capped at
  eight users by its licence and cannot take the cohort, so its one Japanese person is now written
  in kanji rather than romaji, as she now is in every other provider.

  Contract tests under each provider pin all of it - the five scripts, the decomposed name, the
  astral surname, the ideographic space and the ASCII logins - because the previous coverage was
  lost to exactly the kind of tidying these rows invite. The decomposed name is built from
  codepoints in the generators rather than typed, since an editor that normalised the file on save
  would erase the case without changing a visible character.

  Counts move with it: Active Directory 296 users to 311, Entra 305 to 329, Authentik 306 to 330,
  FreeIPA 333 to 357. Bulk group membership and contractor flags shift as a side effect, because
  the generators pick those by indexing into a pool whose size changed.

### Fixed

- **A refused confirmation did not stop an Active Directory teardown.** The guard read the
  operator's answer and, on anything other than CONFIRM, returned from `begin{}`. A `return`
  there ends the begin block and nothing else, so `process{}` ran and deleted the whole
  environment regardless. A live run printed "Operation cancelled by user", removed 1114
  objects, reported no errors and handed back `Cancelled = $true`. Unattended it was worse:
  `Read-Host` reads EOF, never matches CONFIRM, so every non-interactive teardown took the
  cancelled path and deleted anyway. The decision is now recorded and enforced in `process{}`,
  the flag is reset per call so a cancelled run cannot cancel the next one in the same session,
  and `Cancelled` is present on both result shapes so a caller can branch on one key. A
  cancelled run now emits its result only under `-PassThru`, like a completed one. **An
  automated teardown must now pass `-Force`**, which was always the documented bypass.

- **The Active Directory batch counters undercounted, badly.** Seeding took two readings of the
  background job list: one to decide what to receive, and a second, later, to decide what to
  keep. Any job that finished between the two readings was no longer "not Completed", so it was
  dropped from tracking without ever being received, and its tally vanished while its objects
  sat in the directory. A live run reported 176 of 311 users and 569 of 688 devices created,
  with none skipped and no error raised. One reading is now taken and the same jobs are
  received, removed and untracked; verified live at 296 of 296 users and 688 of 688 devices.
  Jobs ending Failed or Stopped are drained too: they were never Completed, so the old loop
  neither received nor removed them and `while (Count -gt 0)` could not end.

- **Service account creation failed at random, about one seed run in three hundred.** Windows
  password complexity does not only count character classes: it also refuses any password
  containing the account's sAMAccountName, or a token of its display name three characters or
  longer, split on comma, full stop, hyphen, underscore, space, tab and hash. Active Directory
  reports that as "The password does not meet the length, complexity, or history requirement of
  the domain", naming none of the three, so it reads as a weak generator rather than a password
  that happened to spell a word in the account's own name. The seed prefix puts the token TEST
  on every account it creates, and several service accounts carry a three-letter word of their
  own - Web, SQL, API, CRM, ERP, Dev, Log - which is the length most likely to appear by chance
  in sixteen random characters. Measured across sixty thousand generated passwords, that refused
  about one run in three hundred, with `svc-webapp` joint-first for likelihood, which is the
  account that failed. `New-TestPassword` now takes `-NotContaining` and discards any candidate
  holding a forbidden substring, and `Get-ADTestNameToken` derives the tokens the way Windows
  splits them. Confirmed against a live domain: a password containing `Web` or `TEST` is refused
  on a seeded account and one containing a two-letter fragment, or a token belonging to a
  different account, is accepted.

- **A refused service account left a passwordless account behind.** `New-ADUser` creates the
  object before it sets the password, so a password the domain rejects leaves the account in
  place with none. The existence check at the top of the loop then skipped it on every later
  run as already made, so it stayed passwordless and unreported permanently. Anything the step
  half-creates is now removed, and only when it carries this module's seed tag.

- **Entra teardown left behind any user in a role-assignable group.** Deleting such a user is
  refused with `Authorization_RequestDenied` whatever permissions the caller holds. Deleting the
  group lifts it, and teardown already removes groups before users, but the lift is not
  immediate and the last groups go moments before the users step starts. Measured against a live
  tenant: the same delete succeeds about twenty seconds after the group is soft-deleted, with no
  recycle-bin purge needed. That one refusal is now retried once after a pause instead of being
  reported as a leftover for somebody to chase.

### Documentation

- **Entra replication lag now covers reads taken after a teardown**, which is the direction most
  easily mistaken for a defect. A user listing taken immediately after a successful teardown
  returned 45 seeded users that were already deleted; the same query minutes later returned
  none. The teardown summary is the authority on what happened, not a count taken straight
  afterwards.

## [1.1.0] - 2026-09-11

### Added

- **Active Directory provider, the parity the newer providers had gained.** Every seeded device
  now carries a unique address and resolves: two Active Directory-integrated zones of the seed's
  own, a forward zone under the domain and a reverse zone for 10.214.0.0/16, with an A record
  and its PTR for all 688 devices and eight records around them - aliases, an apex text record,
  and the shapes a review has to notice, an address with no computer, an alias with no target, a
  reverse record with no forward name. Nothing is written into the domain's own zone, and each
  zone carries the seed tag in `adminDescription` so teardown can prove it. Eight of the
  twenty-five service accounts register a service principal name against a seeded server, one on
  a DNS alias rather than the host, and one delegates constrained to the SQL principal;
  unconstrained delegation is never seeded and no switch asks for it. Three fine-grained password
  policies sit over seeded groups at three precedences, one of them with complexity off and
  reversible encryption on. `Remove-TestEnvironment -Keep` now works against Active Directory,
  which was the only provider without it. `New-ADTestDnsZone` and `New-ADTestPasswordPolicy` are
  exported.

  **Safeguards, after a live run went wrong.** A lab domain registered two controllers and
  one had been switched off for weeks. Discovery handed back the dead one part way through a
  seed, so three steps succeeded and every step after them failed the same way, and the host
  could no longer resolve its own domain accounts. Connecting now picks a controller that
  actually answers - a named one first and fatally, then the PDC emulator, then the rest,
  each proved with a real query, falling back to the DNS records when discovery itself is
  broken - and pins every later AD and DNS call to it through module-scope default
  parameters, so none of the two hundred-odd call sites depends on discovery again. If the
  pinned controller stops answering mid-run the seed stops with one sentence instead of
  repeating the same failure once per object. `Remove-TestEnvironment -Keep` covers the new
  types too.

  **Fixed as part of it:** teardown removed password settings objects matching the name
  `EdgeCase*` with no further proof, so a policy an administrator happened to name that way
  would have been deleted by a test teardown. It is claimed by the seed tag now, like everything
  else, and one that looks like ours without the tag is reported and left standing. The device
  `IPAddress` column had been read by nothing: 269 of the 688 were empty and only 305 of the rest
  were unique, so it is regenerated and now drives the DNS records. The service account step
  built a password export entry per account and discarded it, so the password documentation
  never had anything to write and the entries went to the output stream instead - `-PassThru`
  returned twenty-five loose objects ahead of the results, and the export then refused the
  collection as containing nulls. A DNS zone's directory object lives in the DomainDnsZones
  partition, which a default-scoped search cannot see, so the seed tag was never written to
  the zones it created and teardown then refused to remove its own zones; the partition is
  searched explicitly now. Removing a seeded child zone also leaves a delegation behind in
  the domain's own zone, and that is cleaned up with it.

## [1.0.0] - 2026-09-11

The first release as a standalone module, published to the PowerShell Gallery by the tag
`v1.0.0`.

### Added

- **FreeIPA provider, the authentication configuration and member managers.** Two RADIUS
  proxies and two external identity providers, created ahead of the users so that one user
  authenticates through the proxy on the legacy box and one contractor through the GitHub
  provider, each with their login there; beside them a proxy pointed at a decommissioned server
  and a Keycloak pilot at the seed's own address that nobody links to. The shared secrets and
  client secrets are random, sent once, never kept and never returned; a re-run never rotates
  them. Three core groups and two core host groups gain member managers, a user or a group who
  may change the membership without being an administrator. The automount data gains a second
  location whose map shares the first's name and whose key points at a server the realm has no
  host for. The report shows the link on each user, the managers on each group, and every
  proxy and provider with the number of users linked to it. `New-FreeIPAIdentityProvider` is
  exported; the seed is twenty steps and twenty-six seed files.
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
