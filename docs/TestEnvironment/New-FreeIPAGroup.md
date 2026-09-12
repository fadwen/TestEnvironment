---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAGroup
---

# New-FreeIPAGroup

## SYNOPSIS

Creates the seeded FreeIPA groups, nested as Data\FreeIPAGroups.csv describes

## SYNTAX

### __AllParameterSets

```
New-FreeIPAGroup [[-GroupName] <string[]>] [[-Tier] <string[]>] [-ShowProgress] [-PassThru]
 [-WhatIf] [-Confirm]
```

## DESCRIPTION

A row may name member managers, users or seeded groups who may change the group's membership
without being administrators. A manager group is added here, after every group exists, so it can
be a seeded one; a manager user is left to New-FreeIPAUser, because the groups are seeded before
any user exists, and is counted here as deferred.

Creates around a hundred groups in two tiers. The Core tier is twelve hand-designed rows: a
three-deep nesting chain from all-staff down through a department to a non-POSIX team, two sibling
departments, a contractor population outside the chain, a site group with a non-ASCII description, a
deliberately empty group, a group named like an administrator group that is never a member of
admins, a group for service accounts, and an external group wrapped in the POSIX group a trust would
grant a GID through. The Bulk tier is the AD provider's groups mapped across with their own nesting,
which is a graph rather than a tree: some groups have more than one parent, and the seed makes a
child a member of every one of them.

FreeIPA expresses nesting through membership - a child group is a member of its parent - and a
member cannot be added before it exists, so every group is created first, in order of depth, and the
nesting is applied afterwards, one call per parent. User membership is not assigned here:
New-FreeIPAUser places each user once the users exist, which also means the users step can run
against groups that already exist.

Every group carries the seed prefix on its name and the seed marker at the end of its description,
which together are what teardown proves ownership by. A group is created as POSIX, non-POSIX or
external as its row says; a re-run updates the description and leaves the type alone, because
FreeIPA cannot change one.

## EXAMPLES

### Example 1: Creates every seeded group in depth order and nests them

```powershell
New-FreeIPAGroup
```

Output: None

Use case: Called by New-FreeIPAEnvironment as its first step

### Example 2: Rebuilds just the nesting chain

```powershell
New-FreeIPAGroup -GroupName all-staff, dept-engineering, team-platform -PassThru
```

Output: The three group objects, each with its parents

Use case: Testing transitive membership against a chain of known depth

### Example 3: Lists the groups that would be created without creating them

```powershell
New-FreeIPAGroup -WhatIf
```

Output: One WhatIf line per group

Use case: Confirming the prefix and names before seeding a shared realm

### Example 4: Creates the twelve designed groups and none of the volume

```powershell
New-FreeIPAGroup -Tier Core
```

Output: None

Use case: A fast rebuild when the thing under test is behaviour rather than scale

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

### -GroupName

Creates only the named groups, by their Name column. Defaults to all of them. A parent that is not
in the selection and does not already exist is skipped with a warning.

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

### -ShowProgress

Draws a progress bar, one step per row.

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

Creates only Core rows (the twelve designed edge cases) or only Bulk rows (the volume mapped from
the AD provider). Defaults to both.

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

### System.Management.Automation.PSObject

Only when -PassThru is supplied: TotalGroups, CreatedGroups, UpdatedGroups, NestingsApplied, one entry per group under Groups with its CSV key, name, type, parents and category, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
