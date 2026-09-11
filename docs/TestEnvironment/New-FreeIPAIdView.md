---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAIdView
---

# New-FreeIPAIdView

## SYNOPSIS

Creates the seeded ID views and overrides from Data\FreeIPAIdViews.csv and Data\FreeIPAIdOverrides.csv, and applies them to hosts

## SYNTAX

### __AllParameterSets

```
New-FreeIPAIdView [[-ViewName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An ID view is FreeIPA's way of showing a host a different UID, login, shell or home for a user, or a
different name and GID for a group, than the directory holds. The seed creates two: one applied to
the legacy host that renames one user and gives her a different UID, shell and home, changes only
the shell of a second, and renames a group with a new GID; and one applied to no host at all that
holds an override for the disabled user, so the override never takes effect anywhere.

Views are created first, then every override inside each, then the view is applied to the hosts and
host groups its row names. A re-run modifies what exists. The realm's Default Trust View is never
named, and the seed data test pins that no row does.

## EXAMPLES

### Example 1: Creates every seeded view and override and applies the views

```powershell
New-FreeIPAIdView
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, groups and hosts exist

### Example 2: Rebuilds the view the legacy host sees

```powershell
New-FreeIPAIdView -ViewName legacy-view -PassThru
```

Output: The result object with one view

Use case: Testing a report that reads what a host sees rather than what the directory holds

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPAIdView -WhatIf
```

Output: One WhatIf line per view, override and application

Use case: Confirming which hosts gain a view before seeding a shared realm

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

### -ViewName

Creates only the named views, by their Name column, with their overrides. Defaults to all of them.

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

Only when -PassThru is supplied: TotalViews, CreatedViews, UpdatedViews, OverridesCreated, OverridesUpdated, HostsApplied, one entry per view under Views with its CSV key, name and override count, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAUser]()
- [New-FreeIPAHost]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
