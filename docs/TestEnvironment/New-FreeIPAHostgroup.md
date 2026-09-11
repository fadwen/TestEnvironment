---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAHostgroup
---

# New-FreeIPAHostgroup

## SYNOPSIS

Creates the seeded FreeIPA host groups, nested as Data\FreeIPAHostgroups.csv describes

## SYNTAX

### __AllParameterSets

```
New-FreeIPAHostgroup [[-HostgroupName] <string[]>] [[-Tier] <string[]>] [-ShowProgress] [-PassThru]
 [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates thirty host groups in two tiers. The Core tier is eight hand-designed rows: a root server
group with four kinds of server nested beneath it, a group for hosts on an end-of-life operating
system, a group for one office with a non-ASCII description, and a group with no members. The Bulk
tier is one group per kind of device the AD provider's inventory holds, nested under a parent for
the server kinds, and one per office.

FreeIPA expresses nesting through membership, so every group is created first, in order of depth,
and the nesting applied afterwards, one call per parent. Host membership is not assigned here:
New-FreeIPAHost places each host once the hosts exist. FreeIPA also creates a managed netgroup of
the same name for every host group, which goes when the host group does and which the report has to
tell from a netgroup the seed made.

Every host group carries the seed prefix on its name and the seed marker at the end of its
description, which together are what teardown proves ownership by.

## EXAMPLES

### Example 1: Creates every seeded host group in depth order and nests them

```powershell
New-FreeIPAHostgroup
```

Output: None

Use case: Called by New-FreeIPAEnvironment before the hosts step

### Example 2: Rebuilds the root and one child

```powershell
New-FreeIPAHostgroup -HostgroupName all-servers, web-servers -PassThru
```

Output: The two host group objects

Use case: Testing a rule that names a host group with a known membership

### Example 3: Lists the host groups that would be created without creating them

```powershell
New-FreeIPAHostgroup -WhatIf
```

Output: One WhatIf line per host group

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

### -HostgroupName

Creates only the named host groups, by their Name column. Defaults to all of them.

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

### -ShowProgress

Draws a progress bar, one step per row.

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

### -Tier

Creates only Core rows or only Bulk rows. Defaults to both.

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

Only when -PassThru is supplied: TotalHostgroups, CreatedHostgroups, UpdatedHostgroups, NestingsApplied, one entry per host group under Hostgroups with its CSV key, name and parents, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHost]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
