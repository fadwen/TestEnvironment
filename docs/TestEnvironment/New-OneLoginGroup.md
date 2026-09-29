---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginGroup.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginGroup
---

# New-OneLoginGroup

## SYNOPSIS

Creates the seeded groups that the people being seeded will be placed in

## SYNTAX

### __AllParameterSets

```
New-OneLoginGroup [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A OneLogin person is in one group at most, and a group is where a security policy applies, so the seeded groups follow office location the way a real account's do: Seattle HQ, London, New York, US Regional Offices and Remote Workers. Seattle HQ holds most of the people, which makes it the group a per-group report is dominated by.

A group is created with a name and nothing else. New-OneLoginPolicy attaches the seeded policies afterwards, and only ever a seeded policy to a seeded group: a policy that already exists is never attached, because it would change how the group's real members sign in.

A group, like a role, has nothing but its name to say who made it, so teardown proves one by its members: the prefix, no administrators, at least one member, every member a seeded person, and no policy unless it is a prefixed one that is not the account's default. A group nobody in the tiers being seeded will be placed in is therefore not created. A prefixed group that already exists and holds somebody the seed did not make, or has another policy or an administrator, is left alone and reported, and nobody is put in it.

People are placed in their groups by New-OneLoginUser, as each is created.

## EXAMPLES

### Example 1: Create every seeded group

```powershell
New-OneLoginGroup
```

DESCRIPTION: Creates the five office groups
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, before the people who belong in them

### Example 2: Create two groups

```powershell
New-OneLoginGroup -Key london, new-york -PassThru
```

DESCRIPTION: Creates the London and New York groups
OUTPUT: A result object naming them and their ids
USE CASE: Testing how a report treats groups outside headquarters

### Example 3: Preview in an account you care about

```powershell
New-OneLoginGroup -WhatIf
```

DESCRIPTION: Shows every group that would be created, creating none
OUTPUT: A What if: line per group
USE CASE: Checking the seed will not collide with an existing group of the same name

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

Only when -PassThru is supplied: a summary with TotalGroups, CreatedGroups, ReusedGroups, SkippedGroups, Groups and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginUser]()
- [New-OneLoginRole]()

