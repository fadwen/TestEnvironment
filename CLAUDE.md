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
`description`, a custom Okta profile attribute), but the value never does.

### Two safety properties have no parameter, by design

A seeded Conditional Access policy is report-only or disabled and the module cannot create
an enforcing one. A seeded PIM role eligibility is eligible and never active. Both are
asserted by tests under `Tests/Unit/Providers/Entra`, and the tests exist so that adding
`-Enabled` or `-Activate` as a convenience is caught as the regression it would be.

### Teardown asks the container, then proves ownership

Entra teardown enumerates the administrative units the module created; AD teardown
enumerates `OU=TestData`; Okta reads the seed tag. Nothing is deleted for merely matching a
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

### Help is comment-based, and every export must have it

Unlike KrbEtypeInsight, this module does not compile MAML through PlatyPS. `Get-Help` reads
the comment block on each function, the contract test fails any export with no
`.DESCRIPTION`, and the 5.1 and Linux jobs re-check that help is served on both. If PlatyPS
is adopted later, follow the KrbEtypeInsight pattern: `docs/` as source, `.EXTERNALHELP` on
every public function, and a staleness gate - because `.EXTERNALHELP` serves stale MAML in
preference to anything correct.

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
`Tools/` folder that regenerates the seed data.

### `$WhatIfPreference` is inherited by child scopes

Every staging cmdlet in `Publish-Module.ps1` is pinned `-WhatIf:$false`, or the rehearsal
copies nothing and then fails on an empty folder. Only the publish itself is gated by
`ShouldProcess`. When adding a step, decide whether it is genuinely destructive; if not, pin
it.

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
Invoke-Pester ./Tests/Unit              # 1,234 tests, about 50 seconds
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
./Build/Publish-Module.ps1 -WhatIf      # full release rehearsal, publishes nothing
```

The suite reaches no tenant, no domain and no org. `New-EntraEnvironment.Tests.ps1` carries a
backstop that fails loudly if any step escapes the mocks, because the Okta module's suite once
made real network calls for a while after a step was added without one.
