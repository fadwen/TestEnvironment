---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Test-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 14 2026
PlatyPS schema version: 2024-05-01
title: Test-TestEnvironment
---

# Test-TestEnvironment

## SYNOPSIS

Verifies that what is seeded through the active provider matches the seed data

## SYNTAX

### __AllParameterSets

```
Test-TestEnvironment
```

## DESCRIPTION

Dispatches to the provider the session is connected through, which was fixed by
Connect-TestEnvironment. The provider is deliberately not a parameter here: naming it again on every
call is how a script ends up verifying one directory after seeding another, and the connection
already knows the answer.

Every provider answers the same questions. Is every user, group and other object the seed data
describes present, found the way teardown finds them, and is nothing there that the data does not
describe? Does every name match the data by codepoint, so a name that came back mangled is caught
rather than passed by a comparison that calls a decomposed and a precomposed name equal? Does every
membership the data lists or its rules define hold? Object types whose count depends on a licence,
or that do not map one to one onto seed rows, are counted and reported without a verdict.

The result is one object for every provider: Provider, Target, VerifiedOn, Checks, Failed and
Passed. Each check carries Name, Kind, Expected, Found, Missing, Unexpected and Passed, with the
full lists of missing and unexpected names, so a script can act on them and a diff of two results
is about the directory. The console shows one line per check and a verdict.

Memberships are judged on what is missing only. A dynamic group, a group rule and an automember
rule each add members the data never lists, and that is not a fault. Identifiers a directory folds -
a UPN, a SAM account name, an Okta login, a FreeIPA uid or host name, a PingOne username - are
compared case-insensitively; names are compared exactly.

The provider's own parameters are mirrored onto this function at binding time, so -SkipMembership
and -Quiet keep working through it with tab completion and validation intact.

## EXAMPLES

### Example 1: Verifies the connected provider

```powershell
Test-TestEnvironment
```

Output: One line per check, a verdict, and the result object.

Use case: The step between New-TestEnvironment and handing the estate to whoever is going to test
against it.

### Example 2: Gates a pipeline on the estate matching the data

```powershell
if (-not (Test-TestEnvironment -Quiet).Passed) { throw 'The seed does not match the data.' }
```

Output: Nothing on the console; the result object alone.

Use case: A pipeline that seeds and then runs a test suite should stop when the seed is incomplete,
rather than let the suite fail on a missing user.

### Example 3: Lists what failed and why

```powershell
(Test-TestEnvironment -SkipMembership).Checks | Where-Object { $_.Passed -eq $false } | Select-Object Name, Missing, Unexpected
```

Output: The failed checks with the full lists of missing and unexpected names.

Use case: Finding out which of 329 users a partial seed did not create. -SkipMembership skips the
membership reads, which are the expensive part.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### TestEnvironmentVerification

Provider, Target, VerifiedOn, Checks, Failed and Passed. Passed is $true when every check that has
a verdict passed.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-TestEnvironment]()
- [Get-TestEnvironmentReport]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
