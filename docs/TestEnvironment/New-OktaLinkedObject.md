---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaLinkedObject.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaLinkedObject
---

# New-OktaLinkedObject

## SYNOPSIS

Creates the linked object definition and links seeded users with it

## SYNTAX

### __AllParameterSets

```
New-OktaLinkedObject [-SkipLinks] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Linked objects are Okta's real relationship primitive: a named, directional, queryable association
between two users. The seeded users also carry a `manager` profile string, and the difference
between the two is the whole reason this exists.

The profile string is just text. Nothing validates it, nothing indexes it, and nothing stops it
naming somebody who left two years ago. A linked object is a genuine reference that Okta maintains
on both sides, and it disappears when either user does.

A reporting script that reads `manager` and calls it the org chart is wrong in a way that only shows
up when the two disagree. This module deliberately makes them disagree: the mentoring links do not
mirror the management chain, so a script that conflates them produces a visibly different answer
than one that does not.

The definition is org-wide and the links are per user. Removing the definition removes every link
made with it, which is why teardown deletes it after the users are gone.

## EXAMPLES

### Example 1: Defines the linked-object relationship and links the seeded users

```powershell
New-OktaLinkedObject -PassThru
```

### Example 2: Defines the relationship without linking any users

```powershell
New-OktaLinkedObject -SkipLinks -PassThru
```

Output: The definition created, with zero links.

Use case: Testing a report against a linked-object definition nobody has used yet.

### Example 3: Previews the definition and the links

```powershell
New-OktaLinkedObject -WhatIf
```

Output: One WhatIf line for the definition and one per link.

Use case: Confirming which seeded users would be paired before anything is written.

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

### -SkipLinks

Create the definition but do not link any users

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

Only when -PassThru is supplied: a summary with Definitions, LinksCreated and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Links are made between seeded users, so run New-OktaUser first.

## RELATED LINKS

- [New-OktaUser]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
