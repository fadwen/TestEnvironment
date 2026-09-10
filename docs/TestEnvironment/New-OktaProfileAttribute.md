---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaProfileAttribute.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaProfileAttribute
---

# New-OktaProfileAttribute

## SYNOPSIS

Adds the module's custom attributes to the Okta user schemas

## SYNTAX

### __AllParameterSets

```
New-OktaProfileAttribute [[-Attribute] <string[]>] [-Remove] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Okta's base user profile is fixed. Anything beyond it lives in the custom section of a user type's
schema, and it has to exist before a user can be created carrying it, so this runs early in the seed
order and late in the teardown order.

The attributes are chosen for type coverage rather than realism. A lab whose profile is nothing but
strings will not tell you that your export flattens an array to "System.Object[]", that your CSV
writer turns a boolean into "True" where the API wanted true, or that a risk score of zero is falsy
in PowerShell and gets dropped by an `if ($value)` guard. Each of those has a corresponding
attribute here.

Attributes are grouped by user type, because each type has its OWN schema at its own path. Two of
them - labAgencyName and labPurchaseOrder - exist only on the Contractor type, which means an export
that reads the default schema genuinely cannot see them. That is the point of the second type
existing.

One attribute, labSeedTag, is infrastructure rather than test data: it is what
Remove-OktaEnvironment uses to be certain a user was created by this module and not by you.

The schema API replaces the properties it is given and leaves the rest alone, so this is safe to
re-run. -Remove sets each property to null, which is how Okta deletes a custom attribute; there is
no DELETE for these.

## EXAMPLES

### Example 1: Adds every attribute defined in the CSV, to whichever schema each belongs to

```powershell
New-OktaProfileAttribute
```

### Example 2: Adds only the two attributes whose types tend to break exports

```powershell
New-OktaProfileAttribute -Attribute labRiskScore, labEntitlements -PassThru
```

### Example 3: Shows which attributes teardown would delete from the schemas

```powershell
New-OktaProfileAttribute -Remove -WhatIf
```

## PARAMETERS

### -Attribute

Restrict the operation to these attribute names. Defaults to everything in
Data\OktaProfileAttributes.csv.

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

### -Remove

Set the attributes to null, deleting them from the schema. Any user still carrying a value loses it,
so this must run after the users are gone.

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

Only when -PassThru is supplied: a summary with Applied, Removed, Skipped and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Editing the default user type's schema affects every user in the tenant, including your
own admin account.
On a shared tenant, prefer a dedicated user type.

Attributes on a non-default type need that type to exist, so run New-OktaUserType
first, or let New-OktaEnvironment order it for you.

## RELATED LINKS

- [New-OktaUserType]()
- [New-OktaUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
