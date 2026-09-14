# Verify

Live verification, against a real directory. Nothing in this folder ships: `Build/Publish-Module.ps1`
stages an allowlist and this folder is not on it. The unit suite under `Tests/` reaches no tenant,
domain, org, instance, realm or environment by design, so this is where the other half of the
evidence comes from.

## What the module itself offers

`Test-TestEnvironment` is an exported command. After `Connect-TestEnvironment` it compares what the
connected provider holds with the seed data: every seeded object present and found the way teardown
finds it, nothing the module owns that the data does not describe, every name equal by codepoint, and
every membership the data lists or its rules define in place. It returns one object for every
provider, with the full lists of missing and unexpected names, and prints one line per check.

```powershell
Connect-TestEnvironment -Provider PingOne -EnvironmentId $env -ClientId $client -UseStoredSecret
New-TestEnvironment
Test-TestEnvironment            # every check should pass
Remove-TestEnvironment -Force
Test-TestEnvironment -Quiet     # every check should now find nothing
```

## The cycle script

`Invoke-LiveCycle.ps1` runs exactly that sequence through the exported commands and exits non-zero
when the seed does not verify or the teardown leaves anything behind. It imports the module from
the working tree beside it, so what runs is the branch being verified.

```powershell
./Verify/Invoke-LiveCycle.ps1 -Provider Authentik -ConnectParameter @{ BaseUrl = 'https://auth.example.com'; ServiceAccount = $true }
./Verify/Invoke-LiveCycle.ps1 -Provider FreeIPA   -ConnectParameter @{ BaseUrl = 'https://ipa.example.com'; ServiceAccount = $true }
./Verify/Invoke-LiveCycle.ps1 -Provider PingOne   -ConnectParameter @{ EnvironmentId = $env; ClientId = $client; UseStoredSecret = $true }
./Verify/Invoke-LiveCycle.ps1 -Provider Entra     -ConnectParameter @{ TenantId = $tenant; UseSecretStore = $true }
./Verify/Invoke-LiveCycle.ps1 -Provider AD        -ConnectParameter @{}
```

`-SkipSeed` verifies and removes what is already there. `-SkipTeardown` seeds and verifies and
leaves the estate in place. `-WhatIf` runs the seed and its verification and stops before the
teardown. `-PassThru` returns both verification results for inspection.

## What a pass means, and what it does not

A pass means the data and the directory agree on the objects the seed describes by name, and that
nothing the module owns survived teardown. It does not prove every attribute on every object: the
verifier compares identifiers, display names and memberships, and counts the object types whose
rows do not map one to one onto objects or whose number depends on a licence. The provider report
(`Get-TestEnvironmentReport`) is the place to look at the rest.

Run the cycle on Windows PowerShell 5.1 as well as PowerShell 7 before claiming a provider works on
both. The encoding faults the module guards against are invisible on 7.
