---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestUser
---

# New-ADTestUser

## SYNOPSIS

Creates Active Directory test user accounts from CSV data

## SYNTAX

### __AllParameterSets

```
New-ADTestUser [[-BatchSize] <int>] [[-ThrottleLimit] <int>] [[-AccountPassword] <securestring>]
 [-IncludePhotos] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates user accounts in Active Directory based on data from ADUsers.csv. Users are placed in
appropriate department OUs and configured with photos, manager relationships, and other attributes.

## EXAMPLES

### Example 1: Creates all users from ADUsers.csv

```powershell
New-ADTestUser
```

### Example 2: Creates users in batches of 20 with maximum 3 concurrent batches

```powershell
New-ADTestUser -BatchSize 20 -ThrottleLimit 3
```

### Example 3: Shows what users would be created

```powershell
New-ADTestUser -WhatIf
```

### Example 4: Creates users in batches of 10 and returns results object

```powershell
$results = New-ADTestUser -PassThru -BatchSize 10
```

## PARAMETERS

### -AccountPassword

Password every generated user is created with.

A parameter rather than a literal buried in the job script block below, so a caller who wants
something other than the documented default can say so without editing the module. The default is
deliberately a known, weak, shared value: these are lab accounts and being able to sign in as one is
usually the point. Anything random would have to be recorded somewhere to be usable, and this module
already has a vault for the accounts where that matters - the service accounts.

```yaml
Type: System.Security.SecureString
DefaultValue: (ConvertTo-TestSecureString -PlainText 'Password123!')
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -BatchSize

Number of users to process in each batch. Default is 15. Larger batches improve performance but may
consume more resources.

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

### -IncludePhotos

Include user photos from Data/UserImages folder

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

Maximum number of concurrent batch operations. Default is 4. Adjust based on your domain
controller's capacity.

```yaml
Type: System.Int32
DefaultValue: 4
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

Only when -PassThru is supplied: creation results and statistics per batch.

## NOTES

Author: Jeffrey Stuhr

REQUIREMENTS:
- OU structure must exist (run New-ADTestOUStructure first)
- ADUsers.csv must be present in Data folder

## RELATED LINKS

- [New-ADTestOUStructure]()
- [New-ADTestSecurityGroups]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
