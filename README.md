# TestEnvironment

[![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-v1.0.0-blue)](https://www.powershellgallery.com/packages/TestEnvironment)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Quality Gates](https://github.com/fadwen/TestEnvironment/actions/workflows/quality-gates.yml/badge.svg)](https://github.com/fadwen/TestEnvironment/actions/workflows/quality-gates.yml)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)

## 📖 Purpose

**TestEnvironment** seeds a realistic identity environment you can point scripts at, and tears
it down again cleanly. One module, several directories: you name the provider once, at connect
time, and everything afterwards reads the connection rather than being told again.

```powershell
Connect-TestEnvironment -Provider Entra -TenantId <tenant-guid> -CertificateThumbprint <thumb>
New-TestEnvironment
Get-TestEnvironmentReport
Remove-TestEnvironment -Force
```

**Four providers.**

| Provider | Connecting needs | Seeds |
|---|---|---|
| [`Entra`](Providers/Entra/README.md) | a certificate, or a one-off device-code bootstrap | ~1,150 objects held in administrative units |
| [`AD`](Providers/AD/README.md) | nothing — the caller's own Windows identity | ~1,100 objects held in `OU=TestData` |
| [`Okta`](Providers/Okta/README.md) | an OAuth service app, bootstrapped once from an API token | ~60 objects across ten types, seed-tagged |
| [`Authentik`](Providers/Authentik/README.md) | a service account token, bootstrapped once from an API token | ~480 objects across seventeen types, under a user path of their own |

Each provider has its own README, linked above, covering what it seeds, how it connects, what it
needs, and the things about that directory that are only learnable by running against it. This
page covers what every provider shares.

**What every provider guarantees:**

- ✅ **Ownership is proven** — teardown asks the container it created, or the tag it wrote, and nothing is deleted for merely looking like test data
- ✅ **Safe in a directory you care about** — a seeded Entra Conditional Access policy is report-only or disabled, never enforcing; a seeded role eligibility is eligible, never active; neither state is a parameter
- ✅ **`-WhatIf` beats `-Force`** — on every destructive command, pinned by tests
- ✅ **Idempotent** — a re-run reuses what exists rather than duplicating it
- ✅ **One prefix and one tag everywhere** — `ZZ-TEST-` on names and `ZZ-TEST-seed` where the directory can store it, so seeded objects can be found across a hybrid estate with one filter
- ✅ **No dependencies** — no SDKs, no gallery installs, works on a stock 5.1 host; the AD provider imports RSAT at connect time and says so when it is absent
- ✅ **Shared people** — the Entra and AD providers seed the same users, so hybrid identity matching is testable

## 📦 Installation

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/TestEnvironment):

```powershell
Install-PSResource -Name TestEnvironment

# Or, on a host that still only has PowerShellGet v2:
Install-Module -Name TestEnvironment -Scope CurrentUser
```

Requires Windows PowerShell 5.1 or PowerShell 7, and nothing else: `RequiredModules` is empty
and a contract test keeps it that way. The AD provider needs RSAT's `ActiveDirectory` and
`GroupPolicy` modules, which it imports at connect time and names clearly when they are absent.
The Entra, Okta and Authentik providers need nothing beyond a stock host, on any platform.

From a clone:

```powershell
git clone https://github.com/fadwen/TestEnvironment.git
Import-Module .\TestEnvironment\TestEnvironment.psd1
```

## 🚀 Quick Start

Every session is the same four steps, and only the connect line differs by provider. The first
run against a tenant or org bootstraps the credential the module uses from then on; each provider
README says how.

```powershell
Import-Module TestEnvironment

Connect-TestEnvironment -Provider Entra -TenantId <tenant-guid> -CertificateThumbprint <thumbprint>
Connect-TestEnvironment -Provider AD                                     # the caller's own identity
Connect-TestEnvironment -Provider Okta -OrgUrl https://<org>.okta.com -ServiceApp
Connect-TestEnvironment -Provider Authentik -BaseUrl https://<instance> -ServiceAccount

New-TestEnvironment -WhatIf          # see what it would do
New-TestEnvironment -ShowProgress    # do it
Get-TestEnvironmentReport            # see what you got
Remove-TestEnvironment -WhatIf       # see what teardown would remove, then drop -WhatIf
```

`Get-TestEnvironmentProvider` lists the providers that were discovered and which one is active.

## 💡 Core functions

The provider-agnostic surface. Each of these reads the active connection and forwards to the
provider's own command, mirroring its parameters, so tab completion and binding errors come from
the real command rather than from a pass-through that accepts anything.

### Connection
- **`Connect-TestEnvironment`** — `-Provider` first, then whatever the provider's connect needs; reads the directory back rather than trusting the parameter, so a connection to the wrong one is visible immediately
- **`Disconnect-TestEnvironment`** — clears the credential without unloading the module
- **`Get-TestEnvironmentProvider`** — the providers discovered at import, and which is active
- **`Get-TestAccessToken`** — the token in use and what it carries
- **`New-TestServiceApp`** — bootstraps the identity the module authenticates as from then on, and hands over to it
- **`Get-TestServiceApp`** — what is stored, and whether the credential still works

### Environment
- **`New-TestEnvironment`** — the orchestrator: every step in dependency order, each attempted, recorded and followed by the next
- **`Remove-TestEnvironment`** — teardown, proving ownership before deleting
- **`Get-TestEnvironmentReport`** — Console, JSON, CSV or HTML
- **`Update-TestContainment`** — reconciles container membership where the provider has containers

### Components

Each provider also exports the commands that build one object type at a time, so a single type
can be rebuilt without re-seeding everything: `New-Entra*`, `New-ADTest*`, `New-Okta*` and
`New-Authentik*`. The provider READMEs list them, and `Get-Help` describes each.

## 🧹 Teardown

```powershell
Remove-TestEnvironment -WhatIf                    # always worth running first
Remove-TestEnvironment -Force
Remove-TestEnvironment -Keep Users, Groups -Force # rebuild everything above the directory
```

**Teardown asks the container, then proves ownership.** Entra enumerates the administrative
units it created, AD enumerates `OU=TestData`, Okta reads the seed tag, and Authentik lists the
users under the seed path. Nothing is deleted for merely matching a name, and the fallback paths
that run when a container is gone still refuse objects that are not ours.

**Rights are judged before anything is prompted for.** The Entra provider reads the token's
permissions and the identity's directory roles first. A layer the identity cannot delete is set
aside with one warning rather than confirmed object by object and refused object by object, and
under `Application.ReadWrite.OwnedBy` the applications it does not own are set aside by reading
their owners. The judgement errs towards attempting, and `-SkipPermissionCheck` attempts
everything regardless.

**`-WhatIf` beats `-Force`.** Somebody passing both is asking what would happen, not asking to be
spared the question. `-Force` defeating `-WhatIf` was the worst defect an earlier module ever
shipped, and every Remove suite pins it.

Each provider's README covers the order its directory forces and what happens after a delete.

## 📖 Command help

`Get-Help` on any exported command reads compiled MAML, not the comment block. The source is the
Markdown under `docs\TestEnvironment\`, one page per command plus a module page, and
`about_TestEnvironment` covers what no single command owns: the provider model, the prefix and
seed tag, the two safety properties with no parameter, and how teardown proves ownership.

```powershell
Get-Help New-TestEnvironment -Full
Get-Help about_TestEnvironment
Get-Help New-EntraGroup -Online          # the same page on GitHub
```

Editing help means editing the Markdown and rebuilding:

```powershell
./Build/Build-Help.ps1                   # validates docs\ and rebuilds en-US\TestEnvironment-Help.xml
```

Commit the rebuilt MAML with the Markdown. CI rebuilds from the committed Markdown and fails if
the two disagree, because `.EXTERNALHELP` serves stale compiled help in preference to anything
correct.

## 🧪 Tests

Pester 6 unit tests live in `Tests\Unit\`, mirroring the module's own layout: shared concerns
under `Core\`, provider-specific ones under `Providers\<name>\`, and the module-wide contract at
the root. **1,677 tests, every Graph call, RSAT cmdlet, Okta request and Authentik request mocked**, so the suite reaches no tenant, no domain and no org, creates
nothing, and is safe to run on a workstation.

```powershell
Invoke-Pester -Path .\Tests

Invoke-Pester -Path .\Tests -TagFilter 'Contract'     # manifest, exports, layout, seed data
Invoke-Pester -Path .\Tests -TagFilter 'Safety'       # ownership proof, report-only, scoping
Invoke-Pester -Path .\Tests -TagFilter 'Destructive'  # the teardown paths
```

| File | Covers |
|---|---|
| `Module.Contract.Tests.ps1` | Manifest validity, export agreement, one function per file, no cmdlet shadowing, no stray files at the module root, no duplicate function names across providers, and that nothing provider-specific has crept into `Core` |
| `Core\ConvertTo-TestBase64Url.Tests.ps1` | Padding, URL-unsafe characters, byte-exact round trips including leading zeros |
| `Core\Initialize-TestSecretVault.Tests.ps1` | That a locked store is detected by the error it throws, that an unlock failure is fatal rather than a warning, and that the vault is proven before anything remote is created |
| `Providers\Entra\SeedData.Tests.ps1` | The shape and referential integrity of all 1,100 seed rows |
| `Providers\Entra\New-EntraClientAssertion.Tests.ps1` | That the JWT verifies against its own public key, that `x5t` is the thumbprint **bytes** not its hex text, and that the audience is the v2.0 tenant endpoint |
| `Providers\Entra\Invoke-EntraRequest.Tests.ps1` | UTF-8 both ways, query encoding, pagination and its loop guard, both retry policies, and that the inner exception is set rather than stringified |
| `Providers\Entra\Invoke-EntraBatch.Tests.ps1` | Chunking at twenty, correlation by id rather than position, per-response status, and that only the throttled request is retried |
| `Providers\Entra\Get-EntraSeededObject.Tests.ps1` | That the container is authoritative, that the fallback still runs when it is gone, and that neither claims **anybody else's** objects |
| `Providers\Entra\New-EntraGroup.Tests.ps1` | That a dynamic rule without the seed prefix is refused, that an uncreatable group kind is refused, that nesting is built and groups are contained |
| `Providers\Entra\New-EntraConditionalAccessPolicy.Tests.ps1` | That every policy is report-only, that no parameter can enable one, that an unscoped policy is refused, and that `includeLocations` survives JSON as an array |
| `Providers\Entra\Remove-EntraEnvironment.Tests.ps1` | That `-WhatIf` beats `-Force`, the licence-before-group, untrust-before-delete and units-last ordering, and that the bin purge spares objects that are not ours |
| `Providers\Entra\New-EntraEnvironment.Tests.ps1` | Step ordering, `-Skip`, failure isolation, and a backstop that fails loudly if any step escapes the mocks and reaches a real tenant |
| `Providers\AD\SeedData.Tests.ps1` | The shape and referential integrity of all 1,099 AD seed rows: the 20-character `sAMAccountName` cap, dangling managers and group nesting, group scopes AD will actually accept, and that the people are still shared with the Entra data |
| `Providers\AD\Remove-ADEnvironment.Tests.ps1` | That `-WhatIf` beats `-Force`, and that the group sweep searches the whole container rather than one sub-OU |
| `Providers\AD\New-ADTestGroupPolicy.Tests.ps1` | That a real policy sharing the seeded name is not adopted, linked or deleted |
| `Providers\AD\New-ADTestOU.Tests.ps1` | Path construction and the skip-if-present behaviour a re-run depends on |
| `Providers\AD\Remove-ADTestSecretVault.Tests.ps1` | That the vault is unregistered without resetting a store other modules share |
| `Providers\Authentik\SeedData.Tests.ps1` | The shape and referential integrity of the Authentik seed rows: the three-deep nesting, the contractor flag on every external user, the placeholder a policy uses to name a seeded group, and that regenerating the bulk tier reproduces the committed files byte for byte |
| `Providers\Authentik\Invoke-AuthentikRequest.Tests.ps1` | Page-number pagination and its loop guard, the two error shapes the API answers with, Retry-After on a throttle, and UTF-8 both ways |
| `Providers\Authentik\Get-AuthentikSeededObject.Tests.ps1` | That every type needs its evidence and not just its name, and that the service account is excluded unless asked for |
| `Providers\Authentik\Remove-AuthentikEnvironment.Tests.ps1` | That `-WhatIf` beats `-Force`, the thirteen-step ordering from invitations and tokens through bindings, policies, entitlements, applications, providers, scope mappings and roles to users, groups and rules, and that the service account is left alone by default and removed last when not |
| `Providers\Authentik\New-AuthentikBinding.Tests.ps1` | That every target and subject kind resolves to a seeded object, a user subject is sent as an integer, a rule is bound by its own pk, and a re-run finds the existing binding |
| `Providers\Authentik\New-AuthentikToken.Tests.ps1` | That the secret is never requested or returned, and the three expiry states reach the API as a flag and an absolute time |
| `Providers\Authentik\New-AuthentikEnvironment.Tests.ps1` | Step ordering, `-Skip`, failure isolation, and the backstop |

The AD provider's tests run without RSAT at all, against generated stubs in `Tests\Stubs`, which are appended to `PSModulePath` rather than prepended - so a host that really has RSAT exercises the true binding surface instead.

The compatibility shims for the three modules this one replaced stayed behind in the repository
this module was split from, each with a small suite asserting that the old names still accept
the parameters they used to.

Several are regressions for bugs found while building — the array unrolling, the `continue` in a
`switch`, the unscoped dynamic rule that captured two real accounts, the 404 that placed 72 of 305
users — and each assertion would have caught its bug before a tenant ever saw it.

The backstop in `New-TestEnvironment.Tests.ps1` exists because of a defect in the Okta
module's suite: a step was added to the orchestrator without a mock, and those tests quietly made
real network calls for a while. A suite whose central promise is "this reaches no tenant" has to
enforce that promise rather than assert it in a comment.

## 🏛️ Architecture

```
TestEnvironment/
├── Core/                 shared by every provider: SecretStore, certificates,
│                         password generation, secure strings, base64url,
│                         progress, credential paths
├── Providers/
│   ├── AD/               README.md Private/ Public/ Data/
│   ├── Entra/            README.md Private/ Public/ Data/ Tools/
│   ├── Okta/             README.md Private/ Public/ Data/ + Initialize.ps1
│   └── Authentik/        README.md Private/ Public/ Data/ + Initialize.ps1
├── Public/               the provider-agnostic surface, which dispatches
└── Tests/Unit/           Core/, Providers/<name>/, and the module-wide contract
```

### Where each provider stamps the tag

The tag value is identical everywhere — `ZZ-TEST-seed`, derived from the prefix, because two
settings that must agree for teardown to work are one setting too many. Where it is *stored*
differs, because each directory offers a different native place to put it:

| Provider | Attribute | Note |
|---|---|---|
| `AD` | `adminDescription` | base schema, on `top`, nothing else writes it — see [the AD README](Providers/AD/README.md) |
| `Entra` | `description` | inside a sentence, so it still reads like a description in the portal |
| `Okta` | `labSeedTag` profile attribute, plus the tag appended to descriptions | a custom profile attribute the module defines |
| `Authentik` | `labSeedTag` in the free-form attributes of users and groups; the bracketed tag in an application's description | users additionally sit under a path of their own, which is what a listing can filter on |

**Three modules became one because of what they duplicated.** SecretStore handling, certificate
persistence and password generation had three implementations that were converging on the same
lessons separately — a locked vault detected by the error it throws, a private key that survives
only through a PFX round trip — and each one learned them at its own pace. Those now live in
`Core` and are learned once.

The AD merge is what that looks like in practice: its password generator, its secure-string
helper and its unbiased random-index helper all disappeared into `Core` equivalents that already
existed and were slightly better — Core's generator excludes ambiguous characters, and its
inline reject sampling made the separate index helper dead code.

**The provider split is about what genuinely differs.** An administrative unit is not an OU and a
Conditional Access policy is not an Okta sign-on policy, so the components keep their own names
(`New-EntraGroup`, `New-EntraConditionalAccessPolicy`) rather than hiding behind a shared noun
that would fit none of them. What *is* common — connect, seed, report, tear down — is shared:
`New-TestEnvironment` forwards to the active provider and mirrors its parameters, so you get tab
completion and binding errors from the real command rather than a pass-through that accepts
anything.

Providers are discovered from the `Providers` folder at import, not listed in code. A new one
appears by existing.

**`RequiredModules` is empty, and a contract test enforces it.** The providers do not share a
platform: Entra and Okta reach a REST API from any host, while AD needs RSAT's `ActiveDirectory`
and `GroupPolicy`. Declaring those here would impose a Windows-only, RSAT-only dependency on
somebody who only wanted to seed an Okta org from a container, so the AD provider will import
them lazily at connect time instead.

### The modules this one replaced

`ADTestEnvironment`, `EntraTestEnvironment` and `OktaTestEnvironment` survive as compatibility
shims in the repository this module was split from. Each forwards every name it used to export to
an installed copy of this module, so existing scripts keep working unchanged;
`Connect-EntraTestEnvironment` supplies `-Provider Entra` for you. New work should use the names
above.

## 📊 Module information

- **Version**: 1.0.0
- **Author**: Jeffrey Stuhr (EntraVantage LLC)
- **PowerShell**: 5.1+ (Desktop/Core compatible)
- **Dependencies**: none
- **Providers**: Entra, Active Directory, Okta, Authentik
- **Module GUID**: c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5

## 📞 Support & contact

- **Author**: Jeffrey Stuhr
- **Company**: EntraVantage LLC
- **Blog**: https://www.techbyjeff.net
- **LinkedIn**: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For issues, feature requests, or contributions, please use the
[issue tracker](https://github.com/fadwen/TestEnvironment/issues).

## 🔗 Source

[github.com/fadwen/TestEnvironment](https://github.com/fadwen/TestEnvironment)

## 📄 License

Copyright (c) 2026 EntraVantage LLC. Released under the [MIT License](LICENSE). It comes with no
warranty, which is worth reading literally for a tool that creates and deletes directory objects:
point it only at a tenant, domain or org you can afford to reseed.
