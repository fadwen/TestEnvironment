---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginApiAuthorization.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginApiAuthorization
---

# New-OneLoginApiAuthorization

## SYNOPSIS

Creates the seeded API authorization servers with their scopes and claims, and lets seeded apps ask for them

## SYNTAX

### __AllParameterSets

```
New-OneLoginApiAuthorization [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An API authorization server is what an OpenID Connect app asks for an access token to call an API, so it is where a review of which app may do what to which API looks. Two are seeded:

- Orders API, with a sixty-minute token and three scopes - read, write and admin - of which admin is granted to no app, and a claim read from the zztest_cost_center custom field. Expenses Web may ask for read; Contractor Portal SPA, a public client, may ask for read and write.
- Reports API, with a ten-minute token and one scope, which only Payroll Console may ask for.

Each server's audience is https://api.<lab email domain>/<path>, under example.com by default, never a real host. Its description carries the seed tag inside a sentence, and teardown requires that tag and the prefix on the name together.

Only a seeded app is ever made a client of a seeded server, and only a seeded server is ever given one, so no app outside the seed can ask for a seeded API's tokens and no seeded API issues tokens to one. There is no parameter to name another app. Scopes, claims and clients already on a reused server are kept, and only what the data adds is sent.

## EXAMPLES

### Example 1: Create both seeded servers

```powershell
New-OneLoginApiAuthorization
```

DESCRIPTION: Creates Orders API and Reports API with their scopes, claims and clients
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, once the apps exist

### Example 2: Create one server and see what it holds

```powershell
New-OneLoginApiAuthorization -Key orders-api -PassThru
```

DESCRIPTION: Creates or reuses Orders API
OUTPUT: A result object with ScopesAdded, ClaimsAdded and ClientsLinked
USE CASE: Testing an access review against an API with a scope nobody holds

### Example 3: Preview in an account you care about

```powershell
New-OneLoginApiAuthorization -WhatIf
```

DESCRIPTION: Shows every server, scope, claim and client link that would be made, making none
OUTPUT: A What if: line per object
USE CASE: Checking every client named is a seeded app

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Key

Create only the rows with these keys, from the seed data file. All of them by default.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Return a result object describing what was created, reused and refused.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### System.Management.Automation.PSObject

Only when -PassThru is supplied: a summary with TotalApiAuthorizations, CreatedApiAuthorizations, ReusedApiAuthorizations, ScopesAdded, ClaimsAdded, ClientsLinked, ApiAuthorizations and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginApp]()
- [Test-TestEnvironment]()

