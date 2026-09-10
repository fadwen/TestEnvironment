---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-TestServiceApp.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Get-TestServiceApp
---

# Get-TestServiceApp

## SYNOPSIS

Reports the bootstrapped credential and whether it still works

## SYNTAX

### __AllParameterSets

```
Get-TestServiceApp
```

## DESCRIPTION

Dispatches to the provider the session is connected through, which was fixed by
Connect-TestEnvironment. The provider is deliberately not a parameter here: naming it again on every
call is how a script ends up seeding one directory and tearing down another, and the connection
already knows the answer.

The provider's own parameters are mirrored onto this function at binding time, so provider-specific
switches keep working through it with tab completion and validation intact, and a parameter the
provider does not have fails at binding rather than being quietly dropped.

## EXAMPLES

### Example 1: Runs against the connected provider

```powershell
Get-TestServiceApp
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Proves the stored Entra credential still authenticates

```powershell
Get-TestServiceApp -TestCredential
```

Output: The app's identifiers and a result for the sign-in attempt.

Use case: Diagnosing a failed Connect-TestEnvironment before rotating anything. -TestCredential is
mirrored from the Entra provider.

### Example 3: Reads the Okta service app record for another org

```powershell
Get-TestServiceApp -OrgUrl https://dev-654321.okta.com
```

Output: The client id, key id and credential path recorded for that org.

Use case: Checking which org a credential file belongs to when several have been bootstrapped from
one machine.

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

### TestServiceAppStatus

The provider's description of the stored service app: its identifiers, where the credential lives, and the result of a sign-in when one is requested.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-TestServiceApp]()
- [Get-TestAccessToken]()
- [Connect-TestEnvironment]()
- [about_TestEnvironment]()
