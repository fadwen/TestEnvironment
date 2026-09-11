---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPANetgroup
---

# New-FreeIPANetgroup

## SYNOPSIS

Creates the seeded FreeIPA netgroups from Data\FreeIPANetgroups.csv, with their members

## SYNTAX

### __AllParameterSets

```
New-FreeIPANetgroup [[-NetgroupName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates four netgroups in the shapes an NFS export list or an old NIS map takes: one built from a
user group and two host groups, one from a user and a host named directly, one that contains only
the other two so its members exist only transitively, and one with no members at all. Every netgroup
is created first, then the members are added, because a netgroup can be a member of another and the
nested one has to exist before it is named.

FreeIPA creates a managed netgroup of its own for every host group, with the host group's name, and
refuses a netgroup that would collide with one; the seed data test pins that no seeded netgroup
shares a key with a seeded host group. Those managed netgroups are not ours to create or delete and
are never listed as seeded.

Every netgroup carries the seed prefix on its name and the seed marker at the end of its
description, which together are what teardown proves ownership by.

## EXAMPLES

### Example 1: Creates every seeded netgroup and adds its members

```powershell
New-FreeIPANetgroup
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, groups, hosts and host groups exist

### Example 2: Rebuilds the NFS client netgroup alone

```powershell
New-FreeIPANetgroup -NetgroupName eng-nfs -PassThru
```

Output: The result object with one netgroup

Use case: Testing an export list that names a netgroup with known members

### Example 3: Lists the netgroups that would be created without creating them

```powershell
New-FreeIPANetgroup -WhatIf
```

Output: One WhatIf line per netgroup

Use case: Confirming the prefix before seeding a shared realm

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

### -NetgroupName

Creates only the named netgroups, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalNetgroups, CreatedNetgroups, UpdatedNetgroups, MembershipsApplied, one entry per netgroup under Netgroups with its CSV key and name, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHostgroup]()
- [New-FreeIPAGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
