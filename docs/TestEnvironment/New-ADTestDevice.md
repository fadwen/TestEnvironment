---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestDevice.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestDevice
---

# New-ADTestDevice

## SYNOPSIS

Creates Active Directory test device objects from CSV data

## SYNTAX

### __AllParameterSets

```
New-ADTestDevice [[-BatchSize] <int>] [[-ThrottleLimit] <int>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates computer objects in Active Directory based on data from ADDevices.csv. Devices are placed in
appropriate type OUs (Workstations, Servers, etc.).

## EXAMPLES

### Example 1: Creates all devices from ADDevices.csv using default batch size

```powershell
New-ADTestDevice
```

### Example 2: Creates devices in batches of 20 with maximum 3 concurrent batches

```powershell
New-ADTestDevice -BatchSize 20 -ThrottleLimit 3
```

### Example 3: Creates all devices in batches of 15 and returns results for further processing

```powershell
$results = New-ADTestDevice -PassThru -BatchSize 15
```

## PARAMETERS

### -BatchSize

Number of devices to process in each batch. Default is 10. Larger batches improve performance but
may consume more resources.

```yaml
Type: System.Int32
DefaultValue: 17
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

Returns a PSCustomObject with creation results and statistics

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

### -ThrottleLimit

Maximum number of concurrent batch operations. Default is 5. Adjust based on your domain
controller's capacity.

```yaml
Type: System.Int32
DefaultValue: 6
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

Shows what would be created without making changes

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

Only when -PassThru is supplied: creation counts and the computer objects created, per batch.

## NOTES

Author: Jeffrey Stuhr

## RELATED LINKS

- [New-ADTestOUStructure]()
- [New-ADTestGroupPolicy]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
