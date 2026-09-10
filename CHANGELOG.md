# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The manifest declares 1.0.0. This section becomes `[1.0.0]` with a date when the first tag is
pushed and the release workflow publishes it.

### Added

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

### Changed

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
