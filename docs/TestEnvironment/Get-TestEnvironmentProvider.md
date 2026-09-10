---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-TestEnvironmentProvider.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Get-TestEnvironmentProvider
---

# Get-TestEnvironmentProvider

## SYNOPSIS

Lists the identity providers this module can seed, and which one is active

## SYNTAX

### __AllParameterSets

```
Get-TestEnvironmentProvider
```

## DESCRIPTION

Answers two questions that are easy to get wrong from the outside: what can this module drive, and
what is it pointed at right now.

The second matters more than it sounds. Every command after Connect-TestEnvironment acts on the
active provider without naming it, which is deliberate - restating the provider on every call is how
a script seeds one directory and tears down another - but it does mean the answer is worth being
able to ask for plainly, especially before anything destructive.

Providers are discovered from the Providers folder at import rather than listed in code, so a new
one appears here by existing.

## EXAMPLES

### Example 1: Lists every loaded provider and flags the active one

```powershell
Get-TestEnvironmentProvider
```

Output: Name, Active, DataPath

Use case: Confirming what a session is pointed at before tearing anything down

### Example 2: Shows only the provider the session is connected through

```powershell
Get-TestEnvironmentProvider | Where-Object Active
```

Output: One row, or nothing if Connect-TestEnvironment has not been called.

Use case: A guard at the top of a script that must not seed the wrong directory.

### Example 3: Checks that every provider shipped with its seed data

```powershell
Get-TestEnvironmentProvider | Format-Table Name, SeedFiles, DataPath
```

Output: A row per provider with the count of CSV files under its Data folder.

Use case: Verifying an installation. A provider with zero seed files imported cleanly but cannot
create anything.

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

### TestEnvironmentProviderInfo

One object per provider folder discovered at import: Name, Active, DataPath and SeedFiles.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Connect-TestEnvironment]()
- [Disconnect-TestEnvironment]()
- [about_TestEnvironment]()
