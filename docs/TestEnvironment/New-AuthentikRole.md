---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikRole
---

# New-AuthentikRole

## SYNOPSIS

Creates the seeded Authentik RBAC roles from Data\AuthentikRoles.csv and assigns them to groups

## SYNTAX

### __AllParameterSets

```
New-AuthentikRole [[-RoleName] <string[]>] [-SkipGroups] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three roles: a help-desk role that can see people and reset passwords, an auditor role that
can read applications, providers and the event log, and a role held by nobody. Each role is given
the global permissions its Permissions column lists, by codename, and is then assigned to the seeded
groups its Groups column names, which is how Authentik grants a role: through group membership,
never to a user directly.

This is the Authentik analogue of the Entra provider's directory roles and PIM eligibilities. A
privileged-access report has three shapes to survive: a role reached through a group, a role reached
through a group three levels down the nesting chain, and a role with no holder at all. None of the
roles is a superuser, and none carries a permission that changes anything but a password.

A role has a name and nothing else, so the seed prefix on the name is the only evidence of ownership
it can carry. Group assignment merges with whatever roles the group already holds rather than
replacing them.

## EXAMPLES

### Example 1: Creates every seeded role, grants its permissions and assigns it to its groups

```powershell
New-AuthentikRole
```

Output: None

Use case: Called by New-AuthentikEnvironment after the users step

### Example 2: Creates the help-desk role only

```powershell
New-AuthentikRole -RoleName Lab-Operator -PassThru
```

Output: The role object with its permissions and the groups it was assigned to

Use case: Testing a report that lists who can reset passwords

### Example 3: Lists the roles that would be created without assigning them

```powershell
New-AuthentikRole -SkipGroups -WhatIf
```

Output: One WhatIf line per role

Use case: Reviewing the permission set before it is granted to anyone

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

Creates only the named roles, by their Name column. Defaults to all of them.

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

### -SkipGroups

Creates the roles and grants their permissions without assigning them to any group.

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

Only when -PassThru is supplied: TotalRoles, CreatedRoles, UpdatedRoles, PermissionsAssigned, GroupsAssigned, one entry per role under Roles with its primary key, CSV key, name, permissions and the groups it was assigned to, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikGroup]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
