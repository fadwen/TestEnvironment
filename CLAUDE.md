# TestEnvironment

Seeds a realistic identity test environment - Entra ID, Active Directory or Okta - and tears
it down again cleanly, proving ownership before deleting anything. Published to the
PowerShell Gallery.

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
user or group and the bracketed tag in an Authentik application's description), but the value
never does.

### Two safety properties have no parameter, by design

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
PowerShell cannot hold the decimal serial exactly. A seed file references a stock object solely through a `builtin:` marker from a
short allowed list, and `SeedData.Tests.ps1` refuses every other reference to one.
`New-FreeIPAHbacRule.Tests.ps1` asserts no request reaches an unprefixed rule and no switch
exists to change that.

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

### Teardown asks the container, then proves ownership

Entra teardown enumerates the administrative units the module created; AD teardown
enumerates `OU=TestData`; Okta reads the seed tag; Authentik lists the users under the seed
path and requires the tag on everything that can carry one; FreeIPA filters users and hosts on
the tag in `userclass` server-side and requires the bracketed marker in the description of
everything else, and asks for staged and preserved users separately because `user-find` lists
neither. Nothing is deleted for merely matching a
name pattern, and the fallback paths that run when a container is gone still refuse objects
that are not ours. `-WhatIf` beats `-Force` on every destructive command, and the Remove
suites pin that, because `-Force` defeating `-WhatIf` was the worst defect the AD module ever
shipped.

### The SecretStore is shared per user, not per module

SecretStore configuration is per user. One machine has one store shared by everything that
has ever configured it, and each of the three earlier modules had its own default password.
`Core/Initialize-TestSecretVault.ps1` tries this module's default and then each legacy one,
so a store configured by any of them still opens. Removing a vault must unregister it without
resetting the store other modules share; `Remove-ADTestSecretVault.Tests.ps1` pins that.

Credential records live under `~/.testenvironment`, with read-only fallbacks to the folders
the earlier modules wrote. See `Core/Get-TestCredentialPath.ps1` before changing either.

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
`quality-gates.yml` imports the module under 5.1 to catch it. The build script under
`Build/` is 7.4-only, which is fine: it never ships.

## Checks

```powershell
Invoke-Pester ./Tests/Unit              # about 50 seconds
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
./Build/Build-Help.ps1                  # rebuild MAML after editing docs/
./Build/Publish-Module.ps1 -WhatIf      # full release rehearsal, publishes nothing
```

The suite reaches no tenant, no domain and no org. `New-EntraEnvironment.Tests.ps1` carries a
backstop that fails loudly if any step escapes the mocks, because the Okta module's suite once
made real network calls for a while after a step was added without one.
