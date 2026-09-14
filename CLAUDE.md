# TestEnvironment

Seeds a realistic identity test environment - Entra ID, Active Directory, Okta, Authentik,
FreeIPA or PingOne - and tears it down again cleanly, proving ownership before deleting anything. Published
to the PowerShell Gallery.

## Where the conventions live

General PowerShell conventions - module structure, comment-based help, Pester, error
handling - come from
[Powershell-Copilot-Standards](https://github.com/fadwen/Powershell-Copilot-Standards) and
are mirrored into this repository by `.github/workflows/sync-copilot-standards.yml`:

- `.github/copilot-instructions.md`
- `.github/instructions/`
- `.github/prompts/`

**Those three paths are mirrored with `rm -rf` + `cp`.** A local edit there is silently
reverted on the next sync. Changes belong upstream in the standards repository.

This file is outside the mirror, so it is the right place for anything specific to this
module. What follows is *not* general convention - it is the set of local invariants that
look wrong or arbitrary until you know why, and that are cheap to break by accident.

## Invariants

### `RequiredModules` is empty, and a contract test enforces it

The providers do not share a platform. Entra and Okta reach a REST API from any host; AD
needs RSAT's `ActiveDirectory` and `GroupPolicy`. Declaring those would impose a
Windows-only, RSAT-only dependency on somebody seeding an Okta org from a container, so the
AD provider imports them at connect time and says so clearly when they are absent. The same
goes for the Graph SDK: authentication is a client assertion signed with in-box .NET types
and every call goes through `Invoke-WebRequest`.

`Module.Contract.Tests.ps1` fails on any `RequiredModules` entry, and the Linux job in
`quality-gates.yml` imports the module where none of those modules could exist.

### Providers are discovered, not listed, and load in a fixed order

`Core` first, because providers call into it. Then, for every folder under `Providers/`, its
`Private/`, then `Public/`, then an optional `Initialize.ps1` holding module-scope constants.
Then the shared dispatchers in `Public/`. A provider appears by existing.

`Initialize.ps1` exists because the Okta seed domain once lived in that provider's old root
module and was lost in the consolidation. Nothing failed at import; the `-replace` that used
it matched an empty pattern and mangled an app URL while reporting success. A contract test
now proves every `$script:` variable a provider reads is assigned somewhere.

Every provider shares one session state, so two providers defining the same function name
means the second silently wins. The contract test checks for that too.

### FreeIPA sends in batches; Authentik works on a runspace pool; both keep the row as the unit

The FreeIPA seed steps for users, hosts and DNS records decide each row one at a time - the
`ShouldProcess` call, the options, the lifecycle - and send the resulting commands fifty to a
request through `Invoke-FreeIPABatch`, the realm's JSON-RPC `batch` method. The batch answers one
result per command in order, so a refusal still names its row; `IgnoreError` works per command as
it does on `Invoke-FreeIPARequest`; and a request the realm could not take fails every command in it
rather than leaving any unanswered. The unit suites mock `Invoke-FreeIPABatch` with a shim that
records each command as if it had been a call of its own, so the assertions stay about the commands.

Authentik has no batch endpoint, so `New-AuthentikUser` and the teardown's sweep run their requests
through `Core/Invoke-TestParallel.ps1`, a runspace pool whose workers import the module. A worker
has the module's functions and none of the session's state: `$script:AuthentikConnection` is `$null`
there, so the block takes the connection through `-Parameter`, and a contract test refuses any
`$script:` read inside a worker block, as it does inside a `Start-Job` body. Pester mocks do not
reach a worker either, so the Authentik suites mock `Invoke-TestParallel` with a body that runs the
block inline; a suite that forgets to would call the real instance URL from the workers and fail on
DNS rather than pass. The groups sweep asks for one worker, because a group is deleted before the
group it nests under and that order has to hold.

### Never read module scope inside `Start-Job`

A job runs in a fresh runspace where `$script:Anything` is empty and module functions are
undefined, and neither fails loudly. The AD provider once did this for its prefix: a live
run created 688 computers with no prefix and silently failed to create all 296 users. Pass
values through `-ArgumentList`. A contract test walks every `Start-Job` body for `$script:`
reads and module-function calls.

### The AD commands keep a `Test` infix; the others do not

`New-ADUser`, `New-ADGroup`, `New-ADComputer` and `Get-ADDomain` are real RSAT cmdlets. A
function of the same name would be found ahead of the cmdlet for everything else in the
session, so the AD provider exports `New-ADTestUser` and friends. Entra and Okta ship no
cmdlets to collide with, so theirs are `New-EntraUser` and `New-OktaUser`. This is
collision avoidance, not taste, and it must not be "tidied".

### `ZZ-TEST-` is the prefix and `ZZ-TEST-seed` is the tag, everywhere

Defined once in the root module as `$script:TestEnvironmentDefaultPrefix`. A prefix that
differed by provider could not find this module's objects across a hybrid estate. `ZZ-`
sorts seeded objects to the bottom of a console listing; no wildcard characters, because
they need escaping in an LDAP distinguished name and are rejected in an Entra
`mailNickname`. Where the tag is *stored* differs per provider (`adminDescription`,
`description`, a custom Okta profile attribute, the free-form `attributes` of an Authentik
user or group and the bracketed tag in an Authentik application's description, and a custom
`zzTestSeedTag` user attribute on PingOne, because a PingOne user has no description field), but
the value never does.

### The shared people's names live in one file, and bulk membership is sampled by hash

`Core/Data/SeedPeople.csv` holds the names of every person more than one provider seeds: the nine
written in other writing systems and the nine core people in common. The four seed generators read
it and keep only what is theirs - department, title, manager, population, lifecycle - so one identity
exists in every lab and a name cannot drift between providers, which is what hybrid identity matching
across them depends on. It once did: one person was Owen in two providers and Orla in two others.
The decomposed José lives there as a codepoint sequence, and `SeedPeople.Tests.ps1` pins it, checks
that every generator reads the file, and reads every provider's users file to confirm each shared
person carries exactly the shared names.

The groups nothing in the AD data decides take a sample of the population. The sample is the people
whose hash with the group sorts lowest, never an index into a pool: indexing meant that adding one
person anywhere in the AD data moved every sampled membership in every provider, so a one-row change
produced a five-hundred-line diff and a churned membership could hide a real one.

### Some safety properties have no parameter, by design

A seeded Conditional Access policy is report-only or disabled and the module cannot create
an enforcing one. A seeded PIM role eligibility is eligible and never active. Both are
asserted by tests under `Tests/Unit/Providers/Entra`, and the tests exist so that adding
`-Enabled` or `-Activate` as a convenience is caught as the regression it would be.

The Authentik analogue: a seeded flow never becomes anyone's default. `New-AuthentikFlow` never
writes to the brand and never creates, edits or binds anything to a flow whose slug lacks the
seed prefix; a seeded flow is attached only to providers behind seeded applications.
`New-AuthentikFlow.Tests.ps1` asserts both and that no switch exists to change them.

The FreeIPA analogue: a rule the realm shipped with is never touched. `allow_all`,
`allow_systemd-user`, `global_policy`, the stock privileges, `ipa-http-delegation`, the Default
Trust View, the `default` automount location, the automember default groups, the stock CA ACL
`hosts_services_caIPAserviceCert` and the shipped certificate profiles are never created,
modified, enabled or disabled; every HBAC, sudo, RBAC, policy, delegation, view, automount,
automember and CA ACL request names an object with the seed prefix, and a stock service,
privilege, profile or CA may only be a *member* of a seeded one. An automember rebuild is always
scoped to the seeded users and hosts by name, never the realm. A certificate is proved by its
owner - the CA is asked what the seeded principals hold, never for a subject pattern - and is
only ever revoked, by the hex serial the CA returned, because a CA has no delete and Windows
PowerShell cannot hold the decimal serial exactly. The seed never writes into the realm's DNS
zone: its hosts live in a zone of their own under the realm's domain, with a reverse zone for a
private /16, and a zone is the seed's only by the SOA contact it wrote - a zone of the seed's
name with any other contact is refused, never modified, never adopted. That is why a seeded host
is `zz-test-web01.zz-test-lab.<domain>`; `Get-FreeIPASeedZone` is the one place the zones are
derived. A RADIUS proxy carries the marker in its description; an external identity provider has
no description and is owned by its prefix alone, like a permission. Their secrets are generated,
sent once and never kept: nothing in the module can read one back, and a re-run never rotates
one. A seed file references a stock object solely through a `builtin:` marker from a
short allowed list, and `SeedData.Tests.ps1` refuses every other reference to one.
`New-FreeIPAHbacRule.Tests.ps1` asserts no request reaches an unprefixed rule and no switch
exists to change that.

The PingOne analogue: no seeded population is ever the environment's default, because the default
decides where every user created without a population lands, and no public client (a single-page or
native application with no secret) is created without S256 PKCE. Neither has a parameter;
`New-PingOnePopulation.Tests.ps1` and `New-PingOneApplication.Tests.ps1` assert both. PingOne's own
applications and built-in resources are matched by type, never name, and never touched.

### The Entra connect reads the tenant's licences once, and unknown means attempt everything

`Get-EntraCapability` runs inside `Connect-EntraEnvironment` and puts `Capabilities` on the
connection: `Known`, `EntraP1`, `EntraP2`. `New-EntraEnvironment` skips Conditional Access
policies without P1 and role eligibilities without P2 with one message, and the report and the
verifier do not ask Graph for eligibilities a tenant without P2 cannot hold. The rule that keeps
this safe: `Known = $false` - the app could not read `/subscribedSkus` - means every step runs, as
it did before the probe existed. The probe may remove noise; it may never remove a step the
tenant would have run. Teardown deliberately ignores it: a tenant whose P2 lapsed may still hold
eligibilities Graph will not show, and deleting the role definitions would orphan them.

### Every HTTP provider handles text encoding the same way, and none of it is optional

Windows PowerShell 5.1 corrupts non-ASCII text in both directions, silently, and PowerShell 7 hides
both faults, so a provider tested only on 7 looks correct. Every HTTP call the module makes therefore
goes through `Core/Invoke-TestWebRequest.ps1`, which is the one place these four things are done. A
new provider calls it and never calls `Invoke-WebRequest` or `Invoke-RestMethod` itself; the
provider's own request function adds only the base URI, the authorization header, its paging shape
and its error and retry handling:

- **Bodies go out as UTF-8 bytes** with `charset=utf-8`, never as a string. 5.1 sends a string body as
  ISO-8859-1 when no charset is named, whatever the machine's code page. Observed against PingOne: a
  plain `é` went out as the lone byte E9 and was stored as U+FFFD, so every accented Latin name was
  corrupted, and a combining accent, a Han character and an astral pair were each stored as `?`. The
  service accepted every request.
- **Responses are decoded from `RawContentStream` as UTF-8**, never from `.Content` or through
  `Invoke-RestMethod`. 5.1 decodes by the declared charset and falls back to Latin-1; Okta declares
  none, which turned every accented name into mojibake. A service that declares UTF-8 today is not a
  reason to trust it, because the header is not this module's to control.
- **TLS 1.2 is added on the Desktop edition**, only ever adding to the enabled set.
- **The progress bar is suppressed** around `Invoke-WebRequest`, which on 5.1 costs more than the calls.

FreeIPA reaches the same result through `HttpClient`: `StringContent` with UTF-8 out, and
`ReadAsByteArrayAsync` decoded as UTF-8 in. `Invoke-TestWebRequest.Tests.ps1` pins all four things
once, and the Okta, Entra, Authentik and PingOne `Invoke-*Request` suites each still pin both
directions through their own function: a test that the body reaches `Invoke-WebRequest` as UTF-8
bytes, and a test that an accented response is read correctly from the raw stream. FreeIPA's encoding has no test, because it
lives in `Send-FreeIPAHttpRequest`, the one function that suite mocks away; keep that in mind before
changing it.

These lessons were in the code from 1.0.0 and not written down, and the PingOne provider was written
without them. It shipped a string body, and the fault was found only because the seed data carries
writing systems beyond Latin. **Verify a round trip on Windows PowerShell 5.1, and compare by codepoint
or with an ordinal `[string]::Equals`** - never by `.Length`, which three question marks standing in for
a three-unit name pass, and never with `-eq`, which is linguistic and calls a decomposed and a
precomposed name equal.

### The PingOne token comes from the worker's home environment

A worker application's token endpoint belongs to the environment the worker lives in, not the one it
manages. On a trial that is usually Administrators while the objects go into a sandbox, and asking
the sandbox's endpoint is refused with `invalid_client` - the same message as a disabled application
or a bad secret. The connection therefore carries `AuthEnvironmentId` separately from
`EnvironmentId`. `Invoke-PingOneRequest` is the only function that touches the management API, and
the one the tests mock; it follows the encoding rules above, and it emits paginated items one by one
rather than as a wrapped array, because a wrapped array survives `foreach` and breaks `| Where-Object`.

### The FreeIPA provider talks HTTP through a compiled certificate validator

A FreeIPA server presents a certificate from the realm's own CA, which the machine running the
module does not trust. `New-FreeIPAHttpClient` pins that CA from a PEM rather than turning
validation off, and the check runs in a small C# class compiled with `Add-Type` on first use,
because a PowerShell script block handed to `HttpClient` as a validation callback runs on a thread
with no runspace and fails there. That is also why the provider uses `HttpClient` directly instead
of `Invoke-WebRequest`: nothing in `Invoke-WebRequest` pins an authority on Windows PowerShell.
`Send-FreeIPAHttpRequest` is the only function that touches the network and the one the tests
mock. The seed marker `[ZZ-TEST-seed]` contains square brackets, which are wildcard characters to
`-like`; test for it with `.Contains()`, never `-like`, or the pattern is refused and ownership
discovery finds nothing.

FreeIPA expires every password an administrator sets on the spot. The bootstrap changes the
service account's password as the user immediately, pushes its expiry ten years out, and
`Connect-FreeIPAEnvironment` rotates it and rewrites the record if a realm expires it anyway. A
seeded user whose row says `Current` gets a temporary password and then the real one through the
change-password endpoint; `MustChange` is what an admin-set password already is.

### AD group membership rules are data, and every AD search is scoped to the seed OU

`ADSecurityGroups.csv` carries each group's rule in `MemberFilter`, `MemberSource` and
`MemberLimit`, and `Resolve-ADTestGroupMember` is the only place they are interpreted. They used to
be a 68-branch regex switch on group names inside a `Start-Job` block, searching the whole domain:
a rule of "every enabled account" put twelve real accounts, Administrator among them, into seeded
groups on the lab domain and would have added everyone on a production one, and a group whose name
matched two branches counted its members twice. Every `Get-ADUser` and `Get-ADGroup` lookup in the
seed steps now takes `-SearchBase` on the seed root; `-Identity` cannot, so a device owner is kept
only when its distinguished name sits under the root. `SeedLookupScope.Tests.ps1` parses the step
files and fails on any search that is not scoped, apart from the domain-wide check that a
sAMAccountName is free, which has to be. `SeedData.Tests.ps1` refuses a row that asks for members
and names no rule.

### The AD provider writes DNS, but never into the domain's own zone

Seeded computers resolve, and the records live in two Active Directory-integrated zones the seed
creates: `<prefix>lab.<domain>` and `214.10.in-addr.arpa` for 10.214.0.0/16. `Get-ADTestSeedZone`
is the one place both are derived. A DS-integrated zone is a directory object, so it takes
`adminDescription = ZZ-TEST-seed` like everything else and teardown removes a zone only when it
carries the tag; one that shares the seed's name without it is reported and left alone, never
adopted. The FreeIPA provider owns 10.213.0.0/16 for the same purpose and the two ranges are kept
apart so a hybrid estate can seed both.

Unconstrained delegation is never seeded on an AD service account and no parameter asks for it.
Constrained delegation is, because a review has to tell the two apart, but unconstrained is a
live weakness rather than inert test data. `SeedData.Tests.ps1` pins that the data has no column
that could express it.

### Teardown asks the container, then proves ownership

Entra teardown enumerates the administrative units the module created; AD teardown
enumerates `OU=TestData` and claims password settings objects and DNS zones by the tag, never
by their names - it used to match password policies on `EdgeCase*` alone, which would have
deleted a real policy that happened to share the name; Okta reads the seed tag; Authentik
lists the users under the seed path and requires the tag on everything that can carry one; FreeIPA
filters users and hosts on the tag in `userclass` server-side and requires the bracketed marker in
the description of everything else, and asks for staged and preserved users separately because
`user-find` lists neither; PingOne asks the populations it created for their users, falls back to the
`zzTestSeedTag` attribute only once the schema confirms that attribute exists (a filter naming a
missing attribute is refused with `REQUEST_FAILED`), requires the tag and the prefix together on
everything else, and removes the attribute last because PingOne will not delete one a user still
holds. Nothing is deleted for merely matching a name pattern, and the fallback
paths that run when a container is gone still refuse objects that are not ours. `-WhatIf` beats
`-Force` on every destructive command, and the Remove suites pin that, because `-Force` defeating
`-WhatIf` was the worst defect the AD module ever shipped.

### Reports share one shape and one file writer; the console format is each provider's own

Every `Get-<Provider>EnvironmentReport` builds its object with `New-TestEnvironmentReport` and
writes JSON, CSV and HTML with `Export-TestEnvironmentReport`, both in `Core/`. The shape is
Provider, Target, GeneratedOn, the provider's own facts, Counts, Sections and one property per
section; `Sections` is the order the console, the CSV folder and the HTML page all follow, so the
formats cannot drift from each other or from what `-PassThru` returns. The writer is the one place
the file encoding is decided - UTF-8, because `Export-Csv` on Windows PowerShell defaults to ASCII
and the seeded names exist to catch exactly that - and the one place a list becomes a joined column
instead of `System.Object[]`. The three parameters are the same on every provider, `-OutputFormat`,
`-OutputPath` and `-PassThru`, and Entra keeps `-Format` and `-Path` as aliases only so an old call
binds; a contract test in `Tests/Unit/Public/Get-TestEnvironmentReport.Tests.ps1` holds every
provider folder to them. The console rendering is deliberately not shared: what a person wants to
see of an Okta org and of a FreeIPA realm are different things. Every provider that stores a
credential also carries `[Alias('UseStoredCredential')]` on its own switch for it, and the same
contract test pins that.

### Verification finds objects the way teardown does, and compares names by codepoint

`Test-TestEnvironment` dispatches to `Test-<Provider>Environment`, and every one of those reads the
directory through the same ownership discovery teardown uses (`Get-<Provider>SeededObject`,
`Select-ADTestOwnedObject`), never through a name pattern of its own, so what verification calls
present is exactly what teardown would remove. Expected names come from the seed data through the
same rule the seed applies - the prefix, `Resolve-FreeIPASeedName`, `Resolve-PingOneSeedName`, the
UPN suffix - and the per-provider tests build a directory from the seed files by those rules and
require a pass, so a naming rule that drifts between seed and verifier fails there. Names are
compared with `[string]::Equals(..., Ordinal)` and never `-eq`, which is the point of the feature:
a decomposed and a precomposed name are equal to `-eq` and different on the wire. Memberships are
judged on what is missing only, because dynamic groups, AD group rules and FreeIPA automember rules
add members the data never lists. The result shape is built only by `New-TestEnvironmentCheck` and
`New-TestEnvironmentVerification` in `Core/`, so one renderer prints every provider.

`Compare-TestEnvironment` is the cross-provider half: each provider's `Get-<Provider>IdentitySnapshot`
reduces the users teardown would find to a `TestIdentity` whose `Key` is the login with that
provider's additions stripped, and `Compare-TestIdentitySnapshot` matches by key, then by display
name folded for case and Unicode normalisation, and judges only the codepoint equality of the
matched names. A display name is never compared against a name composed from parts; PingOne stores
no display name and a composed one would put the family name last for the Han and Japanese people.

### The SecretStore is shared per user, not per module

SecretStore configuration is per user. One machine has one store shared by everything that
has ever configured it, and each of the three earlier modules had its own default password.
`Core/Initialize-TestSecretVault.ps1` tries this module's default and then each legacy one,
so a store configured by any of them still opens. Removing a vault must unregister it without
resetting the store other modules share; `Remove-ADTestSecretVault.Tests.ps1` pins that.

Credential records live under `~/.testenvironment`, with read-only fallbacks to the folders
the earlier modules wrote. `Core/Get-TestCredentialRoot.ps1` is the one place that folder is
created and restricted, `Export-TestCredentialRecord` and `Import-TestCredentialRecord` are the one
place a record is written and read - the protected secret or the vault pointer, the UTF-8 bytes
with no byte order mark, the folder and file restricted to the current user, a record that lies
about its protection refused - and each provider's `Export-<Provider>Credential` and
`Import-<Provider>Credential` name only the fields its record carries. The Okta version 1 record
predates the shared shape and is read by the Okta wrapper alone.

### Help is compiled, and stale help beats correct help

`docs/TestEnvironment/*.md` is the source; `en-US/TestEnvironment-Help.xml` is the artifact.
After editing anything under `docs/`, run `./Build/Build-Help.ps1` and commit the rebuilt
MAML in the same change. The `help` job in `quality-gates.yml` compares a fresh build against
the committed file byte for byte, and PlatyPS is pinned to 1.0.3 there because a release that
changed the emitted XML at all would fail that comparison for a reason nobody changed.

`.EXTERNALHELP` means a user is served the stale content rather than falling back to anything
correct, which is why the staleness gate is a hard failure.

### The MAML filename carries a capital H

`en-US/TestEnvironment-Help.xml`, matching every `.EXTERNALHELP TestEnvironment-Help.xml`
keyword. `Export-MamlCommandHelp` produces that name while most documentation writes
`-help.xml`. On Windows the mismatch is invisible; on a case-sensitive filesystem `Get-Help`
silently falls back to a reflected stub and every command loses its help. The Linux jobs exist
to catch exactly this, and `Build-Help.ps1` asserts the produced name rather than assuming it.

### Only exports carry `.EXTERNALHELP`; the provider commands behind them do not

Each provider's `Public/` folder holds both exported commands (`New-EntraUser`) and the
connect, seed, report and teardown commands that are reached only through the shared
dispatchers (`New-EntraEnvironment`). The dispatchers mirror those commands' parameters, but
they are not exported, PlatyPS never sees them, and they keep full comment-based help. An
exported function's comment block is `.EXTERNALHELP` plus a one-line `.SYNOPSIS` and nothing
else; the prose lives in its Markdown. `Build-Help.ps1` resolves each export to its file
rather than sweeping the folder, and `Module.Contract.Tests.ps1` pins both halves.

When adding an exported function, write full comment-based help first, run
`New-MarkdownCommandHelp` to seed the Markdown from it, and only then add `.EXTERNALHELP` and
trim the block. The other order produces empty templates with no error.

### The compatibility shims depend on a private helper's name

`ADTestEnvironment`, `EntraTestEnvironment` and `OktaTestEnvironment` survive as shims in
the repository this module was split from. Each reflects its parameters by running the
*private* `Get-TestProviderParameter` inside this module's scope. Renaming that helper, or
changing its `-CommandName` contract, does not break the shims visibly: they import cleanly,
list every command, and export parameterless signatures that fail only when somebody passes
`-TenantId`. Treat the helper's name and signature as public.

### `Tests/Stubs` is appended to `PSModulePath`, never prepended

The stubs are generated stand-ins for the RSAT and SecretManagement cmdlets the AD suites
mock. Pester cannot attach a mock to a command that does not exist, and the CI runner has
neither module. Appending means a host that really has RSAT binds against the real cmdlets
and exercises the true surface. The `.psm1` files are generated by `Update-ADTestStub.ps1`
on an RSAT host - do not hand-edit them.

### Never `Publish-PSResource -Path .`

This repository *is* the module root, so packaging it directly ships the working tree: the
tests, the generated stubs, `.github`, and every object under `.git`. Gallery versions can
never be deleted, only unlisted, and the `.nupkg` stays downloadable afterwards.

Always publish through `Build/Publish-Module.ps1`, which stages an **allowlist** into a
git-ignored `out/`. A new folder does not ship until it is named in `$shipFiles` or
`$shipFolders`. `Providers/` ships whole, including each `Data/` folder and the Entra
`Tools/` folder that regenerates the seed data. `en-US/` ships the compiled help and the
about topic; `docs/` and `maml/` do not ship.

### `$WhatIfPreference` is inherited by child scopes

Every staging cmdlet in `Publish-Module.ps1` is pinned `-WhatIf:$false`, or the rehearsal
copies nothing and then fails on an empty folder. `Build-Help.ps1` is called with
`$WhatIfPreference` saved and cleared, or `Export-MamlCommandHelp` compiles nothing and the
rehearsal stops verifying the very help build it exists to verify; it cannot take
`-WhatIf:$false` directly because it declares `[CmdletBinding()]` without
`SupportsShouldProcess`. Only the publish itself is gated by `ShouldProcess`. When adding a
step, decide whether it is genuinely destructive; if not, pin it. Test `-WhatIf` and
`-SkipHelpBuild` in combination, not just individually.

### Empty manifest URI keys break the pack

`IconUri = ''` is not "no icon" - the nuspec writer emits an empty `<iconUrl>` and NuGet
aborts with `IconUrl cannot be empty`. Same for `HelpInfoURI`. Omit the key entirely.
`Publish-Module.ps1` checks for this.

### Releases are tag-driven and the tag must match the manifest

`git tag v<ModuleVersion> && git push origin v<ModuleVersion>` triggers
`.github/workflows/release.yml`, which re-runs the full quality gates, verifies the tag
against `ModuleVersion`, stages, imports the staged tree in a fresh process, and publishes.

A version number is consumed permanently on first publish. Bump `ModuleVersion`, update
`CHANGELOG.md`, and tag - the workflow blocks a tag that disagrees with the manifest.

The API key is the `PSGALLERY_API_KEY` repository secret, passed as an environment variable
rather than `-ApiKey`. Locally the script resolves `-ApiKey`, then `$env:PSGALLERY_API_KEY`,
then a SecretManagement secret named `PSGallery-ApiKey`.

## Targeting

Windows PowerShell 5.1 and PowerShell 7, `CompatiblePSEditions = Desktop, Core`. That rules
out the ternary and null-coalescing operators, `ForEach-Object -Parallel`, and anything else
7-only, anywhere in `Core/`, `Providers/` or `Public/`. The `desktop` job in
`quality-gates.yml` imports the module under 5.1 to catch it, and then runs the whole suite
there, because 5.1 also differs at run time in ways a suite run on 7 cannot see: string bodies
sent as Latin-1, responses decoded by their declared charset, a name above the basic plane
measured one longer. The build script under
`Build/` is 7.4-only, which is fine: it never ships.

## Checks

```powershell
Invoke-Pester ./Tests/Unit              # about a minute on a workstation; CI runs it shuffled
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
./Build/Build-Help.ps1                  # rebuild MAML after editing docs/
./Build/Publish-Module.ps1 -WhatIf      # full release rehearsal, publishes nothing
```

The suite reaches no tenant, no domain, no org, no instance, no realm and no environment.
`New-EntraEnvironment.Tests.ps1` carries a backstop that fails loudly if any step escapes the
mocks, because the Okta module's suite once made real network calls for a while after a step was
added without one.
