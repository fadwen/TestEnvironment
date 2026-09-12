---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-AE
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestDnsZone
---

# New-ADTestDnsZone

## SYNOPSIS

Creates the seed's own DNS zones and the records in them, so the seeded computers resolve

## SYNTAX

### __AllParameterSets

```
New-ADTestDnsZone [-SkipDeviceRecords] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Every seeded computer carries an address, and until now nothing was ever written to DNS with it, so
a review that reconciles computer objects against name resolution had nothing to find. This creates
two Active Directory-integrated zones and fills them: a forward zone that is a child of the domain
and carries the seed prefix in its name, and a reverse zone for 10.214.0.0/16.

Nothing is written into the domain's own zone. An A record for a machine that does not exist,
sitting in production DNS, would have only its name to say it was ours - the same objection that
makes this module refuse to delete anything by name pattern alone. A zone of its own also means
teardown is one call that takes every record with it.

Ownership works the way it does everywhere else in this provider. A DS-integrated zone is a
directory object, so each zone is stamped with the seed tag in `adminDescription`, and teardown
removes a zone only when it carries the tag. A zone that already exists under the seed's name
without the tag is left alone and reported, never adopted and never deleted.

What goes in: an A record for every seeded device that has an address, with the matching PTR, and
then the records in `Data\ADDnsRecords.csv` - aliases to seeded servers, a text record at the apex,
and the shapes a review has to notice: an alias whose target does not exist, an address record with
no computer behind it, one name with two addresses, and a reverse record whose forward name is
missing.

A domain without the DnsServer module available, or without the integrated DNS role, is reported as
a warning and the step succeeds having created nothing.

## EXAMPLES

### Example 1: Creates both zones, a record per addressed device, and the extra records

```powershell
New-ADTestDnsZone
```

Output: None

Use case: Called by New-ADEnvironment after the devices exist

### Example 2: Creates the zones and the handful of records that are not devices

```powershell
New-ADTestDnsZone -SkipDeviceRecords -PassThru
```

Output: The result object with two zones

Use case: A domain where the seeded computers should not resolve

### Example 3: Lists the zones and records that would be created

```powershell
New-ADTestDnsZone -WhatIf
```

Output: One WhatIf line per zone and record

Use case: Confirming the zone names before seeding a domain you care about

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

### -ShowProgress

Show a progress bar while the device records are written.

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

### -SkipDeviceRecords

Create the zones and the extra records, but no per-device A or PTR records.

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

Only when -PassThru is supplied: DnsAvailable, ZonesCreated, ZonesExisting, DeviceRecords, ExtraRecords, one entry per zone under Zones with its name and kind, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-ADTestDevice]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
