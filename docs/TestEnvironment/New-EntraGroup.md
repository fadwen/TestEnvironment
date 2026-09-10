---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraGroup.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraGroup
---

# New-EntraGroup

## SYNOPSIS

Creates the seeded groups defined in Data\EntraGroups.csv, and their membership

## SYNTAX

### __AllParameterSets

```
New-EntraGroup [[-GroupKey] <string[]>] [[-Tier] <string[]>] [-SkipMembership] [-ShowProgress]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates around a hundred groups: a hand-designed core covering the shapes that break membership
reporting, and bulk volume mapped from ADTestEnvironment, including the nesting AD's own data
describes.

The core is the part worth reading the CSV for - a three-deep nesting chain, a group containing only
other groups, overlapping departments, dynamic membership, a Microsoft 365 group, a role-assignable
group and a deliberately empty one. The bulk is what makes a transitive expansion expensive enough
to be worth measuring.

Only two of Entra's four group flavours can be created here, and that is a hard limit rather than an
omission. Verified against a live tenant: Graph refuses both distribution lists and mail-enabled
security groups with "Cannot Create a mail-enabled security groups and or distribution list",
whatever combination of mailEnabled, securityEnabled and groupTypes is sent. Exchange Online
PowerShell is the only way to make those two.

Groups are created in one batched phase and their membership applied in another, for the same reason
users get their managers separately: a parent can appear above its children in the CSV, and a
nesting chain cannot be built until every link exists.

Dynamic groups are created with their rule already on, and every rule is required to scope itself to
the seed prefix. That is not defensive tidiness. The first live run used (user.userType -eq "Guest")
and Entra immediately put two real external accounts into a seeded group.

## EXAMPLES

### Example 1: Creates every seeded group and wires up its membership

```powershell
New-EntraGroup
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Rebuilds just the nesting chain

```powershell
New-EntraGroup -GroupKey nested-tier1, nested-tier2, nested-tier3 -PassThru
```

Output: The three group objects

Use case: Testing transitive membership expansion against a known-depth chain

### Example 3: Previews the designed groups without their membership

```powershell
New-EntraGroup -Tier Core -SkipMembership -WhatIf
```

Output: One WhatIf line per core group.

Use case: Reviewing the dynamic membership rules before they are created, since every rule must
scope itself to the seed prefix.

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

### -GroupKey

Creates only the named groups, by their Key column. Defaults to all of them.

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

Returns the created groups

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

### -SkipMembership

Creates the groups but assigns no members and builds no nesting

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

Creates only Core rows (the designed shapes) or only Bulk rows (the volume).

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

### EntraGroup

One object per group created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraUser]()
- [New-EntraGuestUser]()
- [New-EntraAdministrativeUnit]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
