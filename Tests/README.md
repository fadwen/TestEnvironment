# The test suite

Part of [TestEnvironment](../README.md).

Pester 6 unit tests live under `Unit\`, mirroring the module's own layout: shared concerns
under `Core\`, provider-specific ones under `Providers\<name>\`, and the module-wide contract at
the root. Every Graph call, RSAT cmdlet, Okta request and Authentik request is mocked, so the
suite reaches no tenant, no domain and no org, creates nothing, and is safe to run on a
workstation. It runs in about a minute.

```powershell
Invoke-Pester -Path .\Tests

Invoke-Pester -Path .\Tests -TagFilter 'Contract'     # manifest, exports, layout, seed data
Invoke-Pester -Path .\Tests -TagFilter 'Safety'       # ownership proof, report-only, scoping
Invoke-Pester -Path .\Tests -TagFilter 'Destructive'  # the teardown paths
```

The `desktop` job in CI runs the suite under Windows PowerShell 5.1 as well, and the Linux job
imports the module where none of the RSAT or SecretManagement modules can exist.

## What the suites pin

Every file opens with a comment saying why it exists. The ones below are the suites that carry a
promise the README makes, or a regression for a bug that reached a real directory.

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
| `Providers\FreeIPA\SeedData.Tests.ps1` | The shape and referential integrity of the FreeIPA seed rows across all twenty-two files: the lifecycle states, the non-POSIX group inside the POSIX chain, the automember rules agreeing with the memberships the data lists, that no row names a stock object except through an allowed `builtin:` reference, that the prefix and tag appear only as placeholders, and that regenerating the bulk tier reproduces the committed files byte for byte |

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
