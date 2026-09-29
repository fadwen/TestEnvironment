---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginPolicy.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginPolicy
---

# New-OneLoginPolicy

## SYNOPSIS

Creates the seeded user security policies and attaches each to seeded groups only

## SYNTAX

### __AllParameterSets

```
New-OneLoginPolicy [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A OneLogin user policy decides how the people in a group sign in: password length and lifetime, how many passwords are remembered, how many failed attempts lock an account and for how long. A group has one policy at most, and a group without one falls back to the account's default. Two are seeded, so that people in the same account are under different rules and a report that assumes one password policy is wrong:

- Strict Office, fourteen characters, sixty days, twenty-four remembered, five attempts and a thirty-minute lock, on Seattle HQ and New York, which hold most of the seeded people.
- Contractor Access, twelve characters, thirty days, six remembered, three attempts and an hour's lock, on Remote Workers.

London and US Regional Offices are given none and fall back to the default, which is a difference a review has to be able to explain.

What keeps this from reaching anybody real, none of which has a parameter:

- A policy is never made the account's default; is_default is never sent. The default decides how everybody without a group policy signs in.
- A policy is attached only to a group the seed may use: a seeded group, or an empty one of the seed's names. A group that holds anybody else is reported and left, because the policy would then govern how they sign in.
- A policy that already exists under a seeded name is reused only when it is not the default and no group outside the seed uses it. Otherwise it is left alone, attached to nothing and reported, because it governs somebody the seed did not make.

A policy has no description, so teardown proves one by the seeded groups using it, and a policy no group in the tiers being seeded would use is not created. Its settings are put back as the data describes on every run.

## EXAMPLES

### Example 1: Create both seeded policies

```powershell
New-OneLoginPolicy
```

DESCRIPTION: Creates Strict Office and Contractor Access and attaches them to their groups
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, once the groups exist

### Example 2: Put one policy's settings back

```powershell
New-OneLoginPolicy -Key strict-office -PassThru
```

DESCRIPTION: Reuses Strict Office and rewrites any setting that no longer matches the data
OUTPUT: A result object; SettingsUpdated counts the policies that were changed back
USE CASE: Repairing a seed after somebody loosened a password rule in the portal

### Example 3: Preview in an account you care about

```powershell
New-OneLoginPolicy -WhatIf
```

DESCRIPTION: Shows every policy and every group attachment that would be made, making none
OUTPUT: A What if: line per policy and per group
USE CASE: Confirming no attachment would land on a group that is not the seed's

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

### -Tier

Create only the policies whose groups the chosen tiers fill, and attach them to those groups only. Both tiers by default.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
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

Only when -PassThru is supplied: a summary with TotalPolicies, CreatedPolicies, ReusedPolicies, SkippedPolicies, SettingsUpdated, GroupsAttached, Policies and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginGroup]()
- [Test-TestEnvironment]()

