---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaUserType.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaUserType
---

# New-OktaUserType

## SYNOPSIS

Creates the second Okta user type and extends its schema

## SYNTAX

### __AllParameterSets

```
New-OktaUserType [[-TypeName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Every Okta org has a default user type, and almost every script written against Okta assumes it is
the only one. A second type is the cheapest way to prove otherwise, because users on it have a
DIFFERENT schema: an export that reads /api/v1/meta/schemas/user/default sees none of their custom
attributes, and a report that groups by profile shape silently splits in two.

Two attributes exist only on the Contractor type - labAgencyName and labPurchaseOrder - so a
default-schema export genuinely cannot see them. That is the whole point of the type existing.

Do not confuse this with the profile.userType STRING attribute, which the seeded users also carry.
They are unrelated: the string is free text on the profile, this is a real object with its own
schema and its own id. Okta named them almost identically, which is a trap worth knowing about
before you write a report that mixes them up.

A user type costs no licence. The users on it still do.

## EXAMPLES

### Example 1: Creates the custom user type and returns the results

```powershell
New-OktaUserType -PassThru
```

### Example 2: Previews the type without creating it

```powershell
New-OktaUserType -TypeName Contractor -WhatIf
```

Output: One WhatIf line for the type.

Use case: Checking the name before a type exists that every later seed step depends on.

### Example 3: Creates the type with no output

```powershell
New-OktaUserType
```

Output: None.

Use case: The first step of a full Okta seed, before New-OktaProfileAttribute and New-OktaUser.

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

### -TypeName

Restrict the operation to these CSV type names

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

Only when -PassThru is supplied: a summary with TotalTypes, CreatedTypes, ExistingTypes, Types and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Runs before New-OktaProfileAttribute and New-OktaUser, because a type has to
exist before its schema can be extended or a user assigned to it.

## RELATED LINKS

- [New-OktaProfileAttribute]()
- [New-OktaUser]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
