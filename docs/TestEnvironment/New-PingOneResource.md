---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOneResource.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOneResource
---

# New-PingOneResource

## SYNOPSIS

Creates the seeded custom resources and the scopes on them

## SYNTAX

### __AllParameterSets

```
New-PingOneResource [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A resource is an API PingOne issues access tokens for, and its scopes are what an
application is granted.
Together they are what an access review is actually reviewing:
not whether a person can sign in to an application, but which permissions that
application ends up holding on their behalf.

Every environment ships two resources of its own, the PingOne API and openid, and this
module never touches either.
They are recognised by type rather than by name, because a
name can be edited in the console and a type cannot.

The two seeded resources are deliberately unalike: one carries three scopes and an
hour-long token, the other a single scope and a fifteen-minute token, so a report that
treats resources as interchangeable has to be wrong about at least one.

The tag goes in the resource's description.
A scope has no field of its own the seed
could claim, so it is owned through the resource it belongs to, and deleting the
resource removes its scopes with it.

Re-running is safe: a resource that already exists is reused, and a scope already on it
is left alone.

## EXAMPLES

### EXAMPLE 1

New-PingOneResource

DESCRIPTION: Creates both seeded resources and their scopes
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, before the applications that are granted them

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

### -Key

Create only the named resources.
All of them by default.

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

Return a result object describing what was created.

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

Only when -PassThru is supplied: a summary with TotalResources, CreatedResources, ReusedResources, ScopesCreated, Resources and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOneApplication]()
