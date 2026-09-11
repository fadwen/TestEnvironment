---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAAutomemberRule
---

# New-FreeIPAAutomemberRule

## SYNOPSIS

Creates the seeded automember rules from Data\FreeIPAAutomemberRules.csv and rebuilds the seeded entries against them

## SYNTAX

### __AllParameterSets

```
New-FreeIPAAutomemberRule [[-Target] <string[]>] [-SkipRebuild] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An automember rule fills a group or host group from an attribute as entries are created: everyone
whose employee type is Contractor, every host classed as a workstation, every host on CentOS, every
host in one office, and one rule whose only condition excludes everything, so it can never match.
Each rule targets a seeded group or host group, and the seed data test pins that the memberships the
data lists already agree with every rule, so the rules explain the directory rather than change it.

The rules are created after the users and hosts, so nothing fired as those were added. To prove the
agreement the seeded entries are then rebuilt against the rules - the users and hosts the module
made, named one by one, and never the realm's own - which is the one way to run an automember
rebuild that touches nothing else.

The realm's default automember groups are never read or set, and every rule carries the seed prefix
on its name and the seed marker at the end of its description.

## EXAMPLES

### Example 1: Creates every seeded rule and rebuilds the seeded users and hosts against them

```powershell
New-FreeIPAAutomemberRule
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, hosts and their groups exist

### Example 2: Creates the rule that can never match

```powershell
New-FreeIPAAutomemberRule -Target empty-hold -SkipRebuild -PassThru
```

Output: The result object with one rule

Use case: Testing a report that flags a rule with no possible members

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPAAutomemberRule -WhatIf
```

Output: One WhatIf line per rule, condition and rebuild

Use case: Confirming which entries a rebuild would touch before seeding a shared realm

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

### -PassThru

Returns the result object.

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

### -SkipRebuild

Creates the rules and conditions without rebuilding the seeded entries against them.

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

### -Target

Creates only the rules for the named groups or host groups, by their Target column. Defaults to all
of them.

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

Only when -PassThru is supplied: TotalRules, CreatedRules, UpdatedRules, ConditionsApplied, EntriesRebuilt, one entry per rule under Rules with its CSV key, name, kind and conditions, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAGroup]()
- [New-FreeIPAHostgroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
