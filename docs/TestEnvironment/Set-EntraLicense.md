---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Set-EntraLicense.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Set-EntraLicense
---

# Set-EntraLicense

## SYNOPSIS

Assigns licences by group and directly, so the assignment path is ambiguous on purpose

## SYNTAX

### __AllParameterSets

```
Set-EntraLicense [[-SkuPartNumber] <string>] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates the one licensing shape that reporting scripts consistently get wrong: a user who holds the
same licence twice, once inherited from a group and once assigned directly to the account.

That user is Priya. She is a member of the seeded licence group, and the same SKU is also assigned
to her account. Graph reports her assignedLicenses identically in both cases - the same skuId, once
- and the only way to tell the paths apart is licenseAssignmentStates, where the inherited entry
carries the group's object id in assignedByGroup and the direct entry carries null. A script that
reads assignedLicenses and stops there cannot distinguish "remove this user from the group" from
"remove the licence from this user", and will report the wrong remediation for one of them.

Marcus is the second case worth having: he is disabled and still licensed, because disabling an
account does not release its licence. That is a real and expensive oversight, and it is invisible
unless a disabled account is actually holding one.

Owen is the third, and he fails on purpose. He has no usageLocation, and Entra refuses to license a
user without one. This is the most common licensing error there is and the message names the reason
clearly, so the failure is reported and the run continues rather than treating it as fatal.

The SKU is chosen at run time from what the tenant actually has spare rather than being hardcoded,
because a seeding module that fails on a tenant with a different subscription mix is not much use.
Anything with no free units is skipped, since assigning from an exhausted SKU fails for a reason
that has nothing to do with this module.

## EXAMPLES

### Example 1: Assigns an automatically chosen spare SKU by group and directly

```powershell
Set-EntraLicense
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Uses a specific SKU

```powershell
Set-EntraLicense -SkuPartNumber POWER_BI_STANDARD -PassThru
```

Output: The group and user assignments made

Use case: Reproducing a licence path against a SKU your own scripts care about

### Example 3: Shows which SKU would be chosen and where it would go

```powershell
Set-EntraLicense -WhatIf
```

Output: One WhatIf line per group and per direct assignment, naming the SKU.

Use case: Confirming the tenant has a spare SKU before the seed consumes it.

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

Returns what was assigned

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

### -SkuPartNumber

Which SKU to assign. Defaults to the first one with free units, preferring the no-cost SKUs that a
tenant is most likely to have spare.

```yaml
Type: System.String
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

### EntraLicenseAssignment

One object per group and per direct assignment made, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraUser]()
- [New-EntraGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
