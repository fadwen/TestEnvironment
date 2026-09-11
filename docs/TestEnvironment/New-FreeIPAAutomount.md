---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAAutomount
---

# New-FreeIPAAutomount

## SYNOPSIS

Creates the seeded automount location, maps and keys from Data\FreeIPAAutomount.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPAAutomount [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Automount is how FreeIPA tells a host which export mounts where, and the seed creates one location
holding two indirect maps and three keys: a wildcard key under /home whose ampersand becomes the
login at mount time, a read-only export under /data, and a direct mount in the auto.direct map
FreeIPA created with the location. Every key points at the seeded NFS host, whose name is written in
the seed file against the seed domain with a prefix placeholder and substituted for the connected
realm's.

The location is the container: FreeIPA creates auto.master and auto.direct inside it on creation,
and teardown removes the location whole, maps and keys with it. The realm's own default location is
never named.

## EXAMPLES

### Example 1: Creates the location, its maps and its keys

```powershell
New-FreeIPAAutomount
```

Output: None

Use case: Called by New-FreeIPAEnvironment once the hosts exist

### Example 2: Creates everything and returns the keys as written

```powershell
New-FreeIPAAutomount -PassThru
```

Output: The result object with three keys naming the NFS host under the realm's domain

Use case: Testing a report that reads automount maps

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPAAutomount -WhatIf
```

Output: One WhatIf line per location, map and key

Use case: Confirming the location name before seeding a shared realm

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

Only when -PassThru is supplied: LocationsCreated, MapsCreated, MapsUpdated, KeysCreated, KeysUpdated, one entry per key under Keys with its location, map, key and mount information as written, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHost]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
