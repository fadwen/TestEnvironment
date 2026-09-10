---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikBinding
---

# New-AuthentikBinding

## SYNOPSIS

Creates the seeded group, user and policy bindings from Data\AuthentikBindings.csv

## SYNTAX

### __AllParameterSets

```
New-AuthentikBinding [[-Target] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates the bindings that grant access without an expression: a group or a user bound straight to an
application, a group or a user bound to an application entitlement, and the event-matcher policy
bound to a notification rule so the rule fires. Each row names a target and a subject. A target is
app:slug, entitlement:slug/name or rule:name; a subject is group:key, user:username or policy:name,
each resolved to the seeded object by the key its own CSV uses.

Authentik has one binding model for all of this, and it evaluates the same way on every target: a
binding with a group or a user subject passes when the request belongs to them, and the target's
policy engine mode decides whether any binding or every binding has to pass. The seeded applications
use any, so a group binding admits its members alongside whatever the expression policies decide,
and the rows are chosen so the two mechanisms disagree on purpose: contractors are admitted to the
wiki by group and refused payroll by policy, a disabled user still holds an entitlement, and one
person is bound directly where every other grant goes through a group.

A binding on a seeded target is ours by construction, so teardown removes every binding on every
seeded application, entitlement and rule before removing the targets. A re-run finds an existing
binding with the same target and subject and does not stack another.

## EXAMPLES

### Example 1: Creates every seeded binding

```powershell
New-AuthentikBinding
```

Output: None

Use case: Called by New-AuthentikEnvironment after the notification rules step, last of the things that bind

### Example 2: Grants the wiki editor entitlement to its team and its disabled holder

```powershell
New-AuthentikBinding -Target entitlement:wiki/Editor -PassThru
```

Output: The two binding objects

Use case: Testing an entitlement report against a grant that should have been revoked

### Example 3: Lists the bindings that would be created

```powershell
New-AuthentikBinding -WhatIf
```

Output: One WhatIf line per binding, naming target and subject

Use case: Reviewing who would be admitted where before seeding a shared instance

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

### -Target

Creates only the bindings on the named targets, as the CSV writes them, for example app:wiki or
entitlement:expenses/Approver. Defaults to all of them.

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

Only when -PassThru is supplied: TotalBindings, CreatedBindings, ExistingBindings, one entry per binding under Bindings with its primary key, target, subject, order and enabled flag, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikEntitlement]()
- [New-AuthentikPolicy]()
- [New-AuthentikNotificationRule]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
