---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaGroup.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaGroup
---

# New-OktaGroup

## SYNOPSIS

Creates the seeded Okta groups and assigns their members

## SYNTAX

### __AllParameterSets

```
New-OktaGroup [[-GroupName] <string[]>] [-SkipMemberAssignment] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates seventeen groups from Data\OktaGroups.csv. The tenant caps users at ten, not groups, so this
is where the environment gets its complexity back: eight users spread across seventeen groups
produce far more interesting membership shapes than eight users in eight groups.

The shapes are chosen on purpose:

- Overlapping membership.
Tomás is in both Engineering and IT, so a script that
  assumes one department per user is wrong about him.
- A group with exactly one member, and a group with none.
Empty is the case reports
  get wrong, because a group that is empty and a group that failed to resolve look
  identical in most output.
- Two groups whose display names are not ASCII, Zürich Site Access and Ingénierie
  Réseau, for the same reason the users have accented names.
- Three groups reserved for group rules, never assigned to directly.
If a rule stops
  working, its group empties out and the manually assigned ones do not, which makes
  the failure visible instead of ambiguous.

Okta groups do not nest, so there is no group-inside-a-group structure to model here. Group rules
are the nearest equivalent, and they live in New-OktaGroupRule.

Existing groups are updated rather than duplicated, so this is safe to re-run.

## EXAMPLES

### Example 1: Creates every group and assigns members

```powershell
New-OktaGroup
```

### Example 2: Creates the group shells only, for testing an assignment script against

```powershell
New-OktaGroup -SkipMemberAssignment -PassThru
```

### Example 3: Previews two groups without creating them

```powershell
New-OktaGroup -GroupName Dept-Engineering, Dept-Sales -WhatIf
```

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

### -GroupName

Restrict the operation to these CSV group names, for example Dept-Engineering. The prefix is added
automatically, so pass the bare name.

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

Return the detailed result object

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

### -SkipMemberAssignment

Create the groups but leave them empty

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

Only when -PassThru is supplied: a summary with TotalGroups, CreatedGroups, UpdatedGroups, MembersAdded, Groups and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Members are matched to users by login, so run New-OktaUser first.
A member that
does not resolve is reported and skipped rather than failing the group.

## RELATED LINKS

- [New-OktaUser]()
- [New-OktaGroupRule]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
