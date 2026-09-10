---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraAdministrativeUnit.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraAdministrativeUnit
---

# New-EntraAdministrativeUnit

## SYNOPSIS

Creates the administrative units that contain the seeded environment

## SYNTAX

### __AllParameterSets

```
New-EntraAdministrativeUnit [[-UnitKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Administrative units are Entra's nearest equivalent to an Active Directory OU, and they are what
makes this environment contained rather than merely named.

ADTestEnvironment puts everything under OU=TestData and can therefore say exactly what it created by
asking the directory. Without a container, an Entra seeder can only ask "what is called
ENTRALAB-something", which is a guess that happens to be usually right. With one, teardown asks the
container for its members and gets an authoritative answer.

Four units are created, one per object class, because **administrative units cannot nest** -
verified against a live tenant, where adding one AU to another is refused with "The reference target
... of type 'AdministrativeUnit' is invalid for the 'members' reference". So AD's sub-OU tree
flattens into four siblings rather than a hierarchy.

Two properties of an AU shape how teardown uses it, and both differ from an OU:

- **An AU is a container, not a parent.** Deleting it does not delete its members -
  verified live, all three test members survived.
So the units are deleted last, after
  their contents, and they exist to identify what to delete rather than to do it.
- **Membership is not exclusive.** An object can belong to several AUs, or to none, and
  it still lives in the tenant root regardless.
Membership is therefore proof that this
  module created something, not proof of where it lives.

Restricted management units are deliberately not used. They would stop anything outside the unit's
own scoped administrators from modifying the members, including the credential this module
authenticates with, which turns a lab environment into one that cannot tear itself down.

## EXAMPLES

### Example 1: Creates the four containers, before anything that goes in them

```powershell
New-EntraAdministrativeUnit
```

Output: None

Use case: The first step of New-EntraEnvironment

### Example 2: Creates only the two units the people-related seeds need

```powershell
New-EntraAdministrativeUnit -UnitKey Users, Groups -PassThru
```

Output: The two administrative unit objects.

Use case: Seeding users and groups on their own, without devices or applications.

### Example 3: Previews the containers without creating them

```powershell
New-EntraAdministrativeUnit -WhatIf
```

Output: One WhatIf line per unit.

Use case: Confirming the prefix and display names before anything is created in a shared tenant.

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

Returns the created units

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

### -UnitKey

Creates only the named units. Defaults to all four.

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

### EntraAdministrativeUnit

One object per administrative unit created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Update-TestContainment]()
- [New-EntraUser]()
- [New-EntraGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
