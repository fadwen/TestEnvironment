# Architecture

Part of [TestEnvironment](../README.md). This page is the design rationale; the
[project instructions](../CLAUDE.md) hold the invariants that are cheap to break by accident, and
each provider's README holds what is specific to its directory.

```
TestEnvironment/
├── Core/                 shared by every provider: SecretStore, certificates,
│                         password generation, secure strings, base64url,
│                         progress, credential paths
├── Providers/
│   ├── AD/               README.md Private/ Public/ Data/
│   ├── Entra/            README.md Private/ Public/ Data/ Tools/
│   ├── Okta/             README.md Private/ Public/ Data/ + Initialize.ps1
│   ├── Authentik/        README.md Private/ Public/ Data/ Tools/ + Initialize.ps1
│   └── FreeIPA/          README.md Data/ Tools/ + Initialize.ps1
├── Public/               the provider-agnostic surface, which dispatches
└── Tests/Unit/           Core/, Providers/<name>/, and the module-wide contract
```

### Where each provider stamps the tag

The tag value is identical everywhere — `ZZ-TEST-seed`, derived from the prefix, because two
settings that must agree for teardown to work are one setting too many. Where it is *stored*
differs, because each directory offers a different native place to put it:

| Provider | Attribute | Note |
|---|---|---|
| `AD` | `adminDescription` | base schema, on `top`, nothing else writes it — see [the AD README](../Providers/AD/README.md) |
| `Entra` | `description` | inside a sentence, so it still reads like a description in the portal |
| `Okta` | `labSeedTag` profile attribute, plus the tag appended to descriptions | a custom profile attribute the module defines |
| `Authentik` | `labSeedTag` in the free-form attributes of users and groups; the bracketed tag in an application's description | users additionally sit under a path of their own, which is what a listing can filter on |
| `FreeIPA` | `userclass` on users and hosts, which `user-find --class` and `host-find --class` filter on; the bracketed tag in the description of everything else that has one | logins carry no prefix, so the class is the whole proof for a user; a sudo command is named by its path and its description is the whole proof for it |

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

**The AD commands keep a `Test` infix and the others do not.** `New-ADUser`, `New-ADGroup`,
`New-ADComputer` and `Get-ADDomain` are RSAT cmdlets, and a function of the same name would be
found ahead of the cmdlet by everything else in the session, so the AD provider exports
`New-ADTestUser` and friends. Entra, Okta and Authentik ship no cmdlets to collide with, so theirs
are `New-EntraUser`, `New-OktaUser` and `New-AuthentikUser`. A contract test enforces that no
function shadows a cmdlet.

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
