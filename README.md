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
- ✅ **Safe in a directory you care about** — a seeded Conditional Access policy is never enforcing, a seeded role eligibility is never active, a seeded Authentik flow is never anyone's default, and none of those states is a parameter
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

## 🔐 Credentials

The Entra, Okta and Authentik providers bootstrap a service identity once and connect as it from
then on. The record of what to connect with lives under `~/.testenvironment/`, outside any working
tree, and never holds a private key: an Entra certificate goes to `Cert:\CurrentUser\My` by
default, or to a SecretStore vault with `-UseSecretStore`, which is the portable path off Windows.

SecretStore is shared in two ways that are not obvious. Its configuration is **per user, not per
vault**, so a store that anything else has already configured keeps that password, and this
module's default will not open it: pass `-VaultPassword` with the existing one, and the module
says so when that is the problem rather than repeating SecretStore's own message. And two vault
names registered against the store are two *names* for one store, not two containers, so every
secret this module writes is namespaced. `SecretManagement` and `SecretStore` are never required;
they are installed on demand, to `CurrentUser` scope, only under the explicit `-UseSecretStore`.

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

**Rights are judged before anything is prompted for.** A layer the identity cannot delete is set
aside with one warning rather than confirmed object by object and refused object by object; the
[Entra README](Providers/Entra/README.md) describes how that judgement is made.

**`-WhatIf` beats `-Force`.** Somebody passing both is asking what would happen, not asking to be
spared the question. `-Force` defeating `-WhatIf` was the worst defect an earlier module ever
shipped, and every Remove suite pins it.

Each provider's README covers the order its directory forces and what happens after a delete.

## 📖 Command help

`Get-Help` on any exported command reads compiled help, and `about_TestEnvironment` covers what no
single command owns: the provider model, the prefix and seed tag, the safety properties with no
parameter, and how teardown proves ownership.

```powershell
Get-Help New-TestEnvironment -Full
Get-Help about_TestEnvironment
Get-Help New-EntraGroup -Online          # the same page on GitHub
```

The source is the Markdown under `docs\TestEnvironment\`; editing help means editing that and
running `./Build/Build-Help.ps1`, which the project instructions describe.

## 🧪 Tests

More than 1,600 Pester tests, with every Graph call, RSAT cmdlet, Okta request and Authentik
request mocked, so the suite reaches no tenant, no domain and no org and is safe to run on a
workstation. It takes about a minute.

```powershell
Invoke-Pester -Path .\Tests
```

[Tests/README.md](https://github.com/fadwen/TestEnvironment/blob/main/Tests/README.md) lists
what each suite pins, the tag filters for the contract, safety and teardown subsets, and the
regressions the suite exists to catch.

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
│   └── Authentik/        README.md Private/ Public/ Data/ Tools/ + Initialize.ps1
├── Public/               the provider-agnostic surface, which dispatches
└── Tests/Unit/           Core/, Providers/<name>/, and the module-wide contract
```

Providers are discovered from the `Providers` folder at import, not listed in code: a new one
appears by existing. What every provider shares lives in `Core`; what genuinely differs keeps its
own name. [docs/Architecture.md](https://github.com/fadwen/TestEnvironment/blob/main/docs/Architecture.md)
has the rationale, where each directory stores the seed tag, and how the three modules this one
replaced still work.

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
