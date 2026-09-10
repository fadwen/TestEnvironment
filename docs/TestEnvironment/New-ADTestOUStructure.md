---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestOUStructure.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestOUStructure
---

# New-ADTestOUStructure

## SYNOPSIS

Creates the standardized organizational unit (OU) structure for AD test data.

## SYNTAX

### __AllParameterSets

```
New-ADTestOUStructure [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates a comprehensive OU structure including TestData parent OU and sub-OUs for Users (by
department), Groups (by category), Devices (by type), and ServiceAccounts. Supports WhatIf for
preview mode.

## EXAMPLES

### Example 1: Creates the complete OU structure

```powershell
New-ADTestOUStructure
```

### Example 2: Shows what would be created without making changes

```powershell
New-ADTestOUStructure -WhatIf
```

### Example 3: Creates the OU structure and returns results for further processing

```powershell
$results = New-ADTestOUStructure -PassThru
```

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

Only when -PassThru is supplied: the organizational units created and those that already existed.

## NOTES

Author: Jeffrey Stuhr

## RELATED LINKS

- [New-ADTestUser]()
- [New-ADTestDevice]()
- [New-ADTestSecurityGroups]()
- [New-ADTestServiceAccount]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
