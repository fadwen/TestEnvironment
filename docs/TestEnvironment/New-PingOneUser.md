---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOneUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOneUser
---

# New-PingOneUser

## SYNOPSIS

Creates the seeded people in their populations, tags them, and applies their group memberships

## SYNTAX

### __AllParameterSets

```
New-PingOneUser [[-Username] <string[]>] [[-Tier] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

Creates the users in the seed data: nineteen hand-designed and 311 generated, or one tier with -Tier.
Each carries its real given and family name, which are never prefixed; the username and email
take the prefix, and the email is under the connection's email domain.

Each person is placed in exactly one seeded population, which is what teardown asks
first.
Each also carries the seed tag in the custom zzTestSeedTag attribute, because a
PingOne user has no description field and a user moved out of a seeded population by
hand would otherwise become impossible to prove as ours.

What the core rows are for, beyond volume:

- A disabled user who still holds every group membership, which membership reports
  routinely count as active.
- MFA switched off where most of the directory has it on.
- A contractor flag stored as the text "true" or "false", because PingOne refuses a
  custom attribute of any type but STRING or JSON.
The string "false" is not falsy in
  PowerShell, so anything casting it reads every contractor as one.
- A unique badge attribute, which PingOne really does enforce: a second user carrying
  the same value is refused with INVALID_DATA rather than accepted.
- The writing systems - Han, Cyrillic, Greek, Arabic, Devanagari, a decomposed name, a
  Turkish dotless i, an eszett and a surname above the basic plane - each of which is
  the only coverage this module has for one way string handling goes wrong.
Every
  username stays plain ASCII, because that is the field PingOne constrains.

Two user states are deliberately not seeded.
verifyStatus belongs to the Verify service
and is NOT_INITIATED on every user created through this API.
An account lock is its own
operation with its own vendor content type rather than a field.
A column written and
silently ignored would be worse than none.

Group memberships are applied here, once every user exists, rather than in the group
step: a group can be created before anyone is in it, but a person cannot be put into a
group that does not exist yet.
A group with a userFilter is skipped, because PingOne
maintains that membership itself and refuses a manual addition.

Re-running is safe: a user that already exists is reused, and a membership already
present is left alone.

## EXAMPLES

### EXAMPLE 1

New-PingOneUser -Tier Core

DESCRIPTION: Creates the nineteen designed people and none of the volume
OUTPUT: None
USE CASE: The fast loop, when the test is behaviour rather than scale

### EXAMPLE 2

New-PingOneUser -Username awhitfield, jmarchetti -PassThru

DESCRIPTION: Creates two named people and reports what happened
OUTPUT: A result object with the created users and any errors
USE CASE: Recreating a person deleted by hand

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

### -ShowProgress

Report progress per user.

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

### -Tier

Create only the Core rows (the hand-designed edge cases) or only the Bulk rows (the
generated volume).
Both by default.

```yaml
Type: System.String[]
DefaultValue: ''
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

### -Username

Create only these people, by their key in the seed data.

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

Only when -PassThru is supplied: a summary with TotalUsers, CreatedUsers, ReusedUsers, MembershipsApplied, Users and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOnePopulation
New-PingOneGroup
New-PingOneProfileAttribute]()
