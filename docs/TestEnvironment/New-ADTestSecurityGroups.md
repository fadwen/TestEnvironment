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
New-ADTestSecurityGroups [-SkipMemberAssignment] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates the security groups in ADSecurityGroups.csv, nests them as the file says, and fills each
one from the membership rule its row carries.

A row with AutoAssignment set is populated by its rule, in three columns:

- MemberFilter  an Active Directory filter, as Get-ADUser -Filter takes it, run over the users
                in the seed OU: "Department -eq 'Sales' -and Title -like '*Manager*'"
- MemberSource  blank for users; DeviceOwner to run the filter over the seeded computers and take
                the people they are managed by
- MemberLimit   a number, to take only the first so many by account name

The rules are data, so adding a group is a change to the file and never to the code, and a row
that asks for members and names no rule fails a test rather than ending up quietly empty. Every
search is scoped to the seed OU: a real account of the same name as a seeded person, or an
enabled account elsewhere in the domain, is never added to a seeded group. A person a rule matches
twice is added once.

The CSV also drives four attributes that scripts operating on the directory expect to find
populated, and which an environment built only from names cannot exercise:

- Mail          the local part of a mail address; the domain is appended at run time
- Info          free-text notes, the attribute group inventory reports surface
- ManagedBy     a display name, resolved to the owner's distinguished name inside the seed OU
- MemberOfGroup groups this group is nested into, semicolon separated

## EXAMPLES

### Example 1: Creates all groups from ADSecurityGroups.csv with automatic membership

```powershell
New-ADTestSecurityGroups
```

### Example 2: Previews every group, nesting and membership without creating anything

```powershell
New-ADTestSecurityGroups -WhatIf
```

### Example 3: Creates all groups and returns results for further processing

```powershell
$results = New-ADTestSecurityGroups -PassThru
```

### Example 4: Creates and nests the groups without populating them

```powershell
New-ADTestSecurityGroups -SkipMemberAssignment
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
