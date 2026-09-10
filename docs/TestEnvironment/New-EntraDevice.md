---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraDevice.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraDevice
---

# New-EntraDevice

## SYNOPSIS

Creates the seeded device objects defined in Data\EntraDevices.csv

## SYNTAX

### __AllParameterSets

```
New-EntraDevice [[-DeviceKey] <string[]>] [[-Tier] <string[]>] [-SkipOwners] [-ShowProgress]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates around seven hundred device objects spanning compliant, non-compliant, unmanaged, mobile,
orphaned and disabled, so that device-conditioned policy and device inventory reporting have
something to disagree about at a realistic size.

These are directory objects, not registered devices, and the distinction bounds what they are good
for. A real device object is created by a device actually joining or registering, which produces a
certificate and a hardware identity. One created through Graph has neither. It is enough to be found
by a report, counted in an inventory, owned by a user and named by a group membership rule. It is
not enough to sign in from, so a Conditional Access evaluation will never see one of these as the
device in play.

Two properties do not behave as the API surface implies. Verified against a live tenant: trustType
and profileType are accepted in the create body and silently come back empty, because Entra sets
them from the registration that never happened. isCompliant, isManaged and accountEnabled do stick.

alternativeSecurityIds.key must be a base64 string. Passing raw bytes makes ConvertTo-Json emit a
JSON array, and Graph rejects it with an OData error about a StartArray node that names neither the
property nor the reason.

## EXAMPLES

### Example 1: Creates every device object and assigns its owner

```powershell
New-EntraDevice
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates only the six designed device states

```powershell
New-EntraDevice -Tier Core
```

Output: None

Use case: A fast rebuild when seven hundred machines are not what you are testing

### Example 3: Creates two specific devices with no owner

```powershell
New-EntraDevice -DeviceKey win-noncompliant, mac-unmanaged -SkipOwners -PassThru
```

Output: The two device objects.

Use case: Reproducing the ownerless-device case a compliance report has to handle.

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

### -DeviceKey

Creates only the named devices, by their Key column. Defaults to all of them.

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

Returns the created devices

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

Draws a progress bar

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

### -SkipOwners

Creates the devices but assigns no registered owners

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

Creates only Core rows (the designed states) or only Bulk rows (the volume).

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

### EntraDevice

One object per device created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraUser]()
- [New-EntraConditionalAccessPolicy]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
