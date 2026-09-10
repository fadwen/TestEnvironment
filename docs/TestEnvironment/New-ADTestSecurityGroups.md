---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestSecurityGroups.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestSecurityGroups
---

# New-ADTestSecurityGroups

## SYNOPSIS

Creates Active Directory test security groups from CSV data

## SYNTAX

### __AllParameterSets

```
New-ADTestSecurityGroups [[-BatchSize] <int>] [[-ThrottleLimit] <int>] [-SkipMemberAssignment]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates security groups in Active Directory based on data from ADSecurityGroups.csv and
automatically assigns users and devices as members based on criteria.

The CSV also drives four attributes that scripts operating on the directory expect to find
populated, and which an environment built only from names cannot exercise:

- Mail          the local part of a mail address; the domain is appended at run time
- Info          free-text notes, the attribute group inventory reports surface
- ManagedBy     a display name, resolved to the owner's distinguished name
- MemberOfGroup groups this group is nested into, semicolon separated

## EXAMPLES

### Example 1: Creates all groups from ADSecurityGroups.csv with automatic membership

```powershell
New-ADTestSecurityGroups
```

### Example 2: Creates groups with larger batches and more concurrent jobs for faster processing

```powershell
New-ADTestSecurityGroups -BatchSize 15 -ThrottleLimit 8
```

### Example 3: Creates all groups and returns results for further processing

```powershell
$results = New-ADTestSecurityGroups -PassThru
```

### Example 4: Creates groups only without automatic member assignment for faster processings

```powershell
New-ADTestSecurityGroups -SkipMemberAssignment
```

## PARAMETERS

### -BatchSize

Number of group member assignments to process in each batch

```yaml
Type: System.Int32
DefaultValue: 15
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

### -SkipMemberAssignment

Creates groups but skips automatic member assignment. This also skips group-into-group nesting from
the MemberOfGroup column, since that is member assignment too.

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

Maximum number of concurrent background jobs for member assignment

```yaml
Type: System.Int32
DefaultValue: 5
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

Only when -PassThru is supplied: creation and membership counts, with any failures.

## NOTES

Author: Jeffrey Stuhr

## RELATED LINKS

- [New-ADTestUser]()
- [New-ADTestOUStructure]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
