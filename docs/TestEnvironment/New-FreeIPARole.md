---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPARole
---

# New-FreeIPARole

## SYNOPSIS

Creates the seeded permissions, privileges and roles from Data\FreeIPAPermissions.csv, Data\FreeIPAPrivileges.csv and Data\FreeIPARoles.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPARole [[-RoleName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

FreeIPA's delegation is a chain: a permission names rights over an attribute set, a privilege
bundles permissions, and a role bundles privileges and is held by users, groups, hosts or services.
The seed builds the chain from the bottom: three permissions, the one that writes scoped by the seed
tag so it can reach nothing the module did not create; three privileges over them; and four roles,
one held through a group and mixing a seeded privilege with a stock read-only one, one held by a
user directly, one held by a host, and one held by nobody.

A permission's filter is written in the seed file as (userclass={tag}) and the tag is substituted at
creation time, so a non-default prefix scopes its own objects. A stock privilege named through
builtin: may be a member of a seeded role, which changes nothing about the privilege, and teardown
removes the role and leaves the privilege. Nothing here ever modifies a permission, privilege or
role the realm shipped with.

## EXAMPLES

### Example 1: Creates every seeded permission, privilege and role

```powershell
New-FreeIPARole
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, groups and hosts exist

### Example 2: Rebuilds the role nobody holds

```powershell
New-FreeIPARole -RoleName empty-role -PassThru
```

Output: The result object with one role

Use case: Testing a role review that flags a privilege with no holder

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPARole -WhatIf
```

Output: One WhatIf line per permission, privilege and role

Use case: Confirming the prefix before seeding a shared realm

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

### -RoleName

Creates only the named roles, by their Name column, and every permission and privilege. Defaults to
all of them.

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

Only when -PassThru is supplied: TotalRoles, CreatedRoles, UpdatedRoles, PermissionsCreated, PrivilegesCreated, MembershipsApplied, one entry per role under Roles with its CSV key, name and privileges, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAGroup]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
