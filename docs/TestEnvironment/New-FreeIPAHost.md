---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAHost
---

# New-FreeIPAHost

## SYNOPSIS

Creates the seeded FreeIPA hosts from Data\FreeIPAHosts.csv, in their host groups

## SYNTAX

### __AllParameterSets

```
New-FreeIPAHost [[-HostName] <string[]>] [[-Tier] <string[]>] [-SkipHostgroups] [-ShowProgress]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates around four hundred host entries in two tiers. The Core tier is eight hand-designed rows: a
web front end with a host key, a database managed by it, a jump host whose tickets need a second
factor, a legacy box on an end-of-life OS, a kiosk in another office, a CI runner, an NFS server
that is a direct member of the root host group, and one record with nothing at all. The Bulk tier is
the AD provider's workstations and servers mapped across with their operating system, hardware,
office and MAC address, each in a host group for its kind and one for its office.

Every seeded host is a record with no keytab. It is added with force, so the realm's DNS is never
consulted or written, and nothing ever enrols; an inventory has to tell a record from a machine, and
has_keytab is how.

Every host carries the seed tag in its userclass, beside the class its row names, and the seed
prefix on its name under the connected realm's domain. Membership is applied after every host
exists, one call per host group; a managed-by relationship is applied last, once both hosts exist.

## EXAMPLES

### Example 1: Creates every seeded host and places it in its host groups

```powershell
New-FreeIPAHost
```

Output: None

Use case: Called by New-FreeIPAEnvironment after the host groups step

### Example 2: Creates the eight designed hosts and none of the inventory

```powershell
New-FreeIPAHost -Tier Core -PassThru
```

Output: The result object with eight hosts

Use case: A fast rebuild when the thing under test is a rule rather than scale

### Example 3: Shows what the record with nothing at all would be created as

```powershell
New-FreeIPAHost -HostName orphan01 -WhatIf
```

Output: One WhatIf line naming the fully qualified host

Use case: Confirming the domain the hosts are written under

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

### -HostName

Creates only the named hosts, by their Name column. Defaults to all of them.

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

Draws a progress bar, one step per row. Worth having at four hundred hosts.

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

### -SkipHostgroups

Creates the hosts without placing them in host groups.

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

Creates only Core rows (the eight designed edge cases) or only Bulk rows (the inventory mapped from
the AD provider). Defaults to both.

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

Only when -PassThru is supplied: TotalHosts, CreatedHosts, UpdatedHosts, MembershipsApplied, one entry per host under Hosts with its CSV key, fully qualified name, class and host groups, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHostgroup]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
