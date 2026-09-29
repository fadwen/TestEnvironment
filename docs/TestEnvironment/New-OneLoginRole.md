---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginRole.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginRole
---

# New-OneLoginRole

## SYNOPSIS

Creates the seeded roles that the people being seeded will hold

## SYNTAX

### __AllParameterSets

```
New-OneLoginRole [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

OneLogin grants app access through roles, so roles are where access lives in a seeded account. There are four, because a OneLogin trial allows five roles and the account's Default role is one of them:

- All Staff, the broad role nearly every licensed employee holds and most apps are granted through. It holds a suspended manager and people whose passwords have lapsed.
- Engineering, a department role, and the one the disabled mapping would hand to every contractor if anybody enabled it.
- Finance, which the data gives one member and the enabled mapping gives a second, so who can reach the payroll app depends on whether mappings have run.
- Contractors, held by one contractor while another is licensed, still waiting for a password, and holds nothing.

A role has nothing but its name to say who made it, so teardown proves one by what it holds: the prefix, no administrators, at least one member, and every member a seeded person and every app a seeded app. A role that nobody in the tiers being seeded will hold is therefore not created. A prefixed role that already exists and holds somebody the seed did not make, or has an administrator, is left alone and reported, and nothing is ever added to it.

People are not added here. A role has to exist before anybody can be put in it, so New-OneLoginUser adds each person to their roles once they exist.

## EXAMPLES

### Example 1: Create every seeded role

```powershell
New-OneLoginRole
```

DESCRIPTION: Creates the four roles
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, before apps are granted to them

### Example 2: Create one role and see what happened

```powershell
New-OneLoginRole -Key finance -PassThru
```

DESCRIPTION: Creates Finance alone
OUTPUT: A result object naming it, or an error naming the plan limit if the account allows no more roles
USE CASE: Rebuilding one role after it was deleted by hand

### Example 3: Create only what a Bulk seed would fill

```powershell
New-OneLoginRole -Tier Bulk -PassThru
```

DESCRIPTION: Creates nothing, and lists every role as skipped, because Bulk people are unlicensed and hold no roles
OUTPUT: A result object whose SkippedRoles names all four
USE CASE: Seeing why a Bulk-only seed has no roles

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

Seed for the Core people only (the hand-designed edge cases) or the Bulk people only (the generated volume). Both by default.

A role or group that nobody in the chosen tiers would hold is not created, because OneLogin gives a role nothing but its name and teardown proves one by the seeded people it holds: an empty one could never be claimed and would be left behind. Bulk people are unlicensed and hold no roles, so -Tier Bulk alone creates no role at all.

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

Only when -PassThru is supplied: a summary with TotalRoles, CreatedRoles, ReusedRoles, SkippedRoles, Roles and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginUser]()
- [New-OneLoginApp]()
- [New-OneLoginMapping]()

