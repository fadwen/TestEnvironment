---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraUser
---

# New-EntraUser

## SYNOPSIS

Creates the seeded users defined in Data\EntraUsers.csv

## SYNTAX

### __AllParameterSets

```
New-EntraUser [[-UserKey] <string[]>] [[-Tier] <string[]>] [-SkipManagers] [-ShowProgress]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates around three hundred cloud users: a hand-designed core chosen to be awkward in ways that
break scripts, and bulk volume mapped from ADTestEnvironment so the same people exist in both labs.
The rationale for each core row is in the Purpose column and in the module README.

Everything is sent through Graph's $batch endpoint in chunks of twenty. At this volume the
difference is not cosmetic: three hundred users take four calls' worth of round trips per phase
rather than three hundred, and the whole step runs in well under a minute instead of a quarter of an
hour.

The work is done in four phases, and the ordering of the last three is forced:

1.
Create the users.
2.
Write the seed tag.
This cannot go in the create call - Graph rejects
   onPremisesExtensionAttributes on POST /users and accepts it on PATCH, which is
   undocumented and consistent.
3.
Set managers, once every user exists, because the CSV names managers by key and a
   manager can appear below their reports in the file.
4.
Place every user in the Users administrative unit, which is what teardown treats as
   proof of ownership.

Passwords are generated, used once, and never returned or stored. Nothing is expected to sign in as
these accounts. forceChangePasswordNextSignIn is deliberately false: an account that must change its
password at first sign-in cannot be used non-interactively by anything, which defeats the point of
seeding it.

## EXAMPLES

### Example 1: Creates every seeded user and their manager chain

```powershell
New-EntraUser
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates only the nine designed edge-case users

```powershell
New-EntraUser -Tier Core -PassThru
```

Output: The created user objects

Use case: A fast rebuild when the volume is not what you are testing

### Example 3: Creates three named users with no manager chain

```powershell
New-EntraUser -UserKey awhitfield, jnino, zmueller -SkipManagers -PassThru
```

Output: The three user objects, two of them with accented names.

Use case: A quick check that an export handles non-ASCII display names.

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

Returns the created users

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

Draws a progress bar

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

### -SkipManagers

Creates the users but not the manager relationships between them

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

Creates only Core rows (the designed edge cases) or only Bulk rows (the volume). Defaults to both.

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

### -UserKey

Creates only the named users, by their Key column. Defaults to all of them.

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

### EntraUser

One object per user created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraGroup]()
- [New-EntraGuestUser]()
- [Set-EntraLicense]()
- [New-EntraAdministrativeUnit]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
