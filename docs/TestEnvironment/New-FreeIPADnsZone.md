---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPADnsZone
---

# New-FreeIPADnsZone

## SYNOPSIS

Creates the seed's own DNS zones and the records in them from Data\FreeIPADnsRecords.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPADnsZone [-SkipRecords] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

The seeded hosts resolve, because the seed keeps its own DNS: a forward zone under the realm's
domain with the prefix in its name, and a reverse zone for a private subnet. The hosts step then
gives each host an address, and FreeIPA writes the A record and the PTR itself. Nothing is ever
written into the realm's own zone.

What this step writes is the two zones and the records the data adds around the hosts: aliases to
seeded hosts, a mail exchanger and a text record at the apex, a service record, and then the shapes
a review has to notice - an alias whose target has no host and no record, an address record with no
host behind it, a name with two addresses, and a reverse record whose forward name does not exist.

Ownership is the SOA contact. Every zone the seed creates carries 'hostmaster.<forward zone>.' as
its administrator address, and a zone is ours only when it does. An existing zone with the seed's
name but another contact is refused with an error, never modified, never adopted: that would be
somebody's DNS.

A realm without DNS - one installed without the integrated server - has no zones to write to. That
is reported as a warning, the step succeeds with nothing created, and the hosts step creates its
hosts without addresses, as it always could.

## EXAMPLES

### Example 1: Creates both zones and every record the data adds

```powershell
New-FreeIPADnsZone
```

Output: None

Use case: Called by New-FreeIPAEnvironment before the hosts, so their addresses have somewhere to go

### Example 2: Creates the zones alone

```powershell
New-FreeIPADnsZone -SkipRecords -PassThru
```

Output: The result object with two zones

Use case: A realm whose hosts should resolve but carry no extra records

### Example 3: Lists the zones and records that would be created

```powershell
New-FreeIPADnsZone -WhatIf
```

Output: One WhatIf line per zone and record

Use case: Confirming the zone names before seeding a shared realm

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

### -SkipRecords

Create the zones and nothing in them.

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

Only when -PassThru is supplied: DnsEnabled, ZonesCreated, ZonesExisting, RecordsCreated, RecordsUpdated, one entry per zone under Zones with its name and kind, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHost]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
