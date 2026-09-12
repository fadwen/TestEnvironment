---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOneProfileAttribute.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOneProfileAttribute
---

# New-PingOneProfileAttribute

## SYNOPSIS

Creates the custom user schema attributes the seed needs, including its ownership marker

## SYNTAX

### __AllParameterSets

```
New-PingOneProfileAttribute [[-Name] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

The first step of a PingOne seed, and the one the rest depends on.

A PingOne user has nowhere to put an ownership marker.
Verified against a live
environment, a user object carries account, address, email, enabled, identityProvider,
lifecycle, mfaEnabled, name, population, username and verifyStatus, and not one of them
is free text this module could claim without overwriting something a person might care
about.
Every other object type - group, population, application, resource - has a
description field and takes the tag there.

So the marker is a custom schema attribute that the seed creates, every seeded user
carries the tag in, and teardown removes last, after the users referencing it.
That
ordering is not cosmetic: PingOne refuses to delete an attribute while users hold a
value in it.

The other attributes exist to be awkward in ways a directory really is.
One is unique,
so a second user carrying the same value is refused rather than quietly accepted.
One
is multivalued, which a report assuming a single value silently truncates.
One is a
boolean, where false and absent are different states that anything testing truthiness
treats alike.
One is JSON, so the seed covers every type PingOne allows.

Re-running is safe.
An attribute that already exists is left as it is rather than
replaced, because replacing it would drop the values every seeded user holds.

## EXAMPLES

### EXAMPLE 1

New-PingOneProfileAttribute

DESCRIPTION: Creates every custom attribute the seed needs
OUTPUT: None
USE CASE: The first step of a seed, run for you by New-TestEnvironment

### EXAMPLE 2

New-PingOneProfileAttribute -Name zzTestSeedTag -PassThru

DESCRIPTION: Creates just the ownership marker
OUTPUT: A result object naming what was created and what already existed
USE CASE: Repairing an environment whose marker attribute was deleted by hand

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

### -Name

Create only the named attributes.
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

Only when -PassThru is supplied: a summary with SchemaId, TotalAttributes, CreatedAttributes, ExistingAttributes, Attributes and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOneUser
New-PingOneEnvironment]()
