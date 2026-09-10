---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaNetworkZone.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaNetworkZone
---

# New-OktaNetworkZone

## SYNOPSIS

Creates the seeded network zones that policies condition on

## SYNTAX

### __AllParameterSets

```
New-OktaNetworkZone [[-ZoneName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A zone is a named set of IP ranges, and it is what turns "allow sign-in" into "allow sign-in from
the office". Policies reference zones by id, so these have to exist before New-OktaPolicy runs.

Two zones, because one is not enough to test with:

- Corporate-Egress, a POLICY zone, referenced by the admin sign-on rule.
This is the
  allow case.
- Suspect-Range, a BLOCKLIST zone.
Blocklist zones behave differently from policy zones
  in evaluation and in the admin console, and a report that treats every zone the same
  gets this wrong.

The ranges are all IANA documentation blocks - 198.51.100.0/24, 203.0.113.0/24 and 192.0.2.0/24.
They are reserved precisely so they can appear in examples without belonging to anybody, which
matters here because a lab zone containing somebody's real address range is a policy that could
really lock somebody out.

## EXAMPLES

### Example 1: Creates every network zone and returns the results

```powershell
New-OktaNetworkZone -PassThru
```

### Example 2: Creates only the corporate egress zone

```powershell
New-OktaNetworkZone -ZoneName Corporate-Egress -PassThru
```

Output: The zone, with its gateway ranges.

Use case: Seeding the one zone a sign-on policy under test refers to.

### Example 3: Previews every zone

```powershell
New-OktaNetworkZone -WhatIf
```

Output: One WhatIf line per zone.

Use case: Checking the IP ranges do not overlap a range that governs real sign-ins in a shared org.

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

Return the detailed result object

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

### -ZoneName

Restrict the operation to these CSV zone names

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

Only when -PassThru is supplied: a summary with TotalZones, CreatedZones, ExistingZones, Zones and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

## RELATED LINKS

- [New-OktaPolicy]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
