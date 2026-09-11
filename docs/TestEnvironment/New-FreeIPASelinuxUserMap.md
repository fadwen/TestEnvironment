---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPASelinuxUserMap
---

# New-FreeIPASelinuxUserMap

## SYNOPSIS

Creates the seeded SELinux user maps from Data\FreeIPASelinuxUserMaps.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPASelinuxUserMap [[-MapName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An SELinux user map tells a host which SELinux user a person becomes when they log in, and it is
scoped either by an HBAC rule or by members of its own, never both. The seed creates three:
engineers become staff_u wherever the engineering HBAC rule admits them, contractors become guest_u
at the kiosk by direct membership, and a disabled map that would make the disabled user unconfined
on the legacy hosts.

Every SELinux user in the seed is one the realm's own order lists, and the seed data test pins that.
A map's members go on after it exists; a map whose row says Enabled FALSE is disabled after
creation. Every map carries the seed prefix on its name and the seed marker at the end of its
description.

## EXAMPLES

### Example 1: Creates every seeded map

```powershell
New-FreeIPASelinuxUserMap
```

Output: None

Use case: Called by New-FreeIPAEnvironment once the HBAC rules exist

### Example 2: Rebuilds the map that follows an HBAC rule

```powershell
New-FreeIPASelinuxUserMap -MapName engineering-staff -PassThru
```

Output: The result object with one map

Use case: Testing a report that resolves a map through its rule

### Example 3: Lists the maps that would be created without creating them

```powershell
New-FreeIPASelinuxUserMap -WhatIf
```

Output: One WhatIf line per map

Use case: Confirming the SELinux users before seeding a shared realm

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

### -MapName

Creates only the named maps, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalMaps, CreatedMaps, UpdatedMaps, MembershipsApplied, one entry per map under Maps with its CSV key, name, SELinux user and whether it is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHbacRule]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
