# Test stubs

## Overview & Purpose

Stand-ins for modules the CI runner does not have, so the ADTestEnvironment suites can run
anywhere. They exist to solve two problems that block the suites on a host without RSAT:

1. `ADTestEnvironment.psd1` declares `RequiredModules = @('ActiveDirectory')` and the root
   module carries `#Requires -Module ActiveDirectory`, so `Import-Module` fails outright.
2. Pester cannot mock a command that does not exist, so every `Get-SecretVault` mock fails
   where SecretManagement is absent.

`Add-ADTestStubPath.ps1` **appends** this directory to `PSModulePath`. Appending rather than
prepending is deliberate: a host that has the real module keeps using it and the suite
exercises the true binding surface, while a host without it falls back to the stub. The
GitHub `windows-latest` runner has neither module, so it takes the stub path; a domain
controller with RSAT does not.

The stubs do not weaken the suites. Every command a test relies on is still mocked; the
stub only makes the command exist so the mock can be attached.

## Provenance

The `.psm1` files are **generated, not hand-written** - do not edit them directly. Each
function is empty and declares exactly the parameters the real cmdlet declares, so a call
the real cmdlet would reject fails here too. Parameter types are carried over wherever the
type ships with PowerShell itself (`SecureString`, `PSCredential`, `bool`, and the
`Nullable<T>` forms the AD cmdlets use); types that live in the AD assemblies are left off,
since the runner has no way to load them.

To regenerate, run `Update-ADTestStub.ps1` on a host that has the real modules - a domain
controller with RSAT and SecretManagement installed:

```powershell
.\Update-ADTestStub.ps1 -OutputPath .
```

## Available Scripts

| Script Name | Description |
|-------------|-------------|
| [Add-ADTestStubPath](./Add-ADTestStubPath.ps1) | Appends this directory to PSModulePath so the stubs are discoverable |
| [Update-ADTestStub](./Update-ADTestStub.ps1) | Regenerates the stub modules from the real cmdlets on an RSAT host |
