---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikGroup
---

# New-AuthentikGroup

## SYNOPSIS

Creates the seeded Authentik groups, nested as Data\AuthentikGroups.csv describes

## SYNTAX

### __AllParameterSets

```
New-AuthentikGroup [[-GroupName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates nine groups: a three-deep nesting chain from All Staff down through a department to a team,
two sibling departments, a contractor population outside the chain, a site group with a non-ASCII
name, a deliberately empty group, and a group named like an administrator group that is never a
superuser group.

Authentik expresses nesting through a group's parents, and a child cannot name a parent that does
not exist yet, so the rows are created in order of depth rather than CSV order. Membership is not
assigned here: an Authentik user carries its group list, so New-AuthentikUser places each user as it
creates them, which also means the users step can run against groups that already exist.

Every group carries the seed tag in its attributes alongside its CSV key, its category and its
description. The tag is what teardown proves ownership by; the key is what lets the users step find
a group by the name the CSV uses rather than the prefixed name Authentik shows.

## EXAMPLES

### Example 1: Creates every seeded group in depth order

```powershell
New-AuthentikGroup
```

Output: None

Use case: Called by New-AuthentikEnvironment as its first step

### Example 2: Rebuilds just the nesting chain

```powershell
New-AuthentikGroup -GroupName All-Staff, Dept-Engineering, Team-Platform -PassThru
```

Output: The three group objects, each with its parent

Use case: Testing transitive membership against a chain of known depth

### Example 3: Lists the groups that would be created without creating them

```powershell
New-AuthentikGroup -WhatIf
```

Output: One WhatIf line per group

Use case: Confirming the prefix and display names before seeding a shared instance

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

### -GroupName

Creates only the named groups, by their Name column. Defaults to all of them. A parent that is not
in the selection and does not already exist leaves the child unparented, with a warning.

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

Only when -PassThru is supplied: TotalGroups, CreatedGroups, UpdatedGroups, one entry per group under Groups with its primary key, CSV key, name and parent, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
