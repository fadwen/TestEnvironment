---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOneGroup.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOneGroup
---

# New-PingOneGroup

## SYNOPSIS

Creates the seeded groups, nests them, and gives the dynamic ones their filters

## SYNTAX

### __AllParameterSets

```
New-PingOneGroup [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

PingOne has two kinds of group membership, and the difference is most of the point of
seeding groups at all.
A static group holds exactly the people put in it.
A group with
a userFilter holds whoever matches the filter, recomputed by the directory, empty until
it evaluates, and not editable by hand.
A report that treats every group as the first
kind is wrong about the second.

What the groups are for:

- A chain three deep - All Staff, Engineering, Team Platform - so membership has to be
  resolved transitively.
Nesting is a membership of one group in another, verified
  against a live environment, not a parent field.
- A dynamic group whose filter matches the whole staff population, and one whose filter
  is perfectly valid and matches nobody, which looks identical to a broken filter in
  every report.
- A group scoped to a population, so a person outside that population cannot be added
  to it however hard a script tries - the refusal comes from the directory.
- An empty group, because an empty group and a failed query look the same.

The tag goes in the description, which is free text nothing else writes.

Membership of people is not applied here.
A group has to exist before anyone can be put
in it, so New-PingOneUser applies memberships once every person exists.
Only nesting,
which is group-to-group, happens in this step, and it happens after every group in the
step has been created so that the order of rows in the file cannot matter.

Re-running is safe: a group that already exists is reused, and a nesting already in
place is left alone.

## EXAMPLES

### EXAMPLE 1

New-PingOneGroup

DESCRIPTION: Creates every seeded group and nests the chain
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, before the users step

### EXAMPLE 2

New-PingOneGroup -Key dyn-staff, dyn-nobody -PassThru

DESCRIPTION: Creates just the two dynamic groups
OUTPUT: A result object naming them and their filters
USE CASE: Testing how a report treats filtered membership

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

Create only the named groups.
All of them by default.

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

Return a result object describing what was created.

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

Only when -PassThru is supplied: a summary with TotalGroups, CreatedGroups, ReusedGroups, NestingsApplied, Groups and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOneUser
New-PingOnePopulation]()
