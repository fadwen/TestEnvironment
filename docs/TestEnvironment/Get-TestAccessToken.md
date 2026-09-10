---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-TestAccessToken.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Get-TestAccessToken
---

# Get-TestAccessToken

## SYNOPSIS

Returns the active provider's access token and its expiry

## SYNTAX

### __AllParameterSets

```
Get-TestAccessToken
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
Get-TestAccessToken
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Returns the bare token for a script that calls the API directly

```powershell
$token = Get-TestAccessToken -AsPlainText
```

Output: The access token as a string rather than a SecureString.

Use case: Reproducing a report against Graph or the Okta API with the same identity this module
seeds with. Both providers mirror -AsPlainText.

### Example 3: Forces a fresh token before a long batch

```powershell
Get-TestAccessToken -Force | Select-Object ExpiresOn
```

Output: The new expiry.

Use case: Starting a seed that will run past the cached token's lifetime. -Force is mirrored from
the Entra provider; Okta refreshes on its own.

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

### TestAccessToken

The active provider's token object, carrying the token and its expiry. Both the Entra and Okta providers mirror -AsPlainText, which returns the bare token string instead.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Connect-TestEnvironment]()
- [Get-TestServiceApp]()
- [about_TestEnvironment]()
