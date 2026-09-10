---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraDirectoryRole.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraDirectoryRole
---

# New-EntraDirectoryRole

## SYNOPSIS

Creates custom directory role definitions

## SYNTAX

### __AllParameterSets

```
New-EntraDirectoryRole [[-RoleKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Custom directory roles are Entra's answer to least privilege, and the closest thing it has to Okta's
custom admin roles. Three are created, spanning the shapes that matter: a read-only role, a narrow
write role, and one that spans two resource types.

**Definitions only. Nothing is assigned to anybody.** That is a deliberate limit rather than an
oversight. A role definition is inert - it grants nothing until it is assigned to a principal at a
scope - so creating one is safe in a tenant that is in real use, while assigning one is a privilege
grant that should be a human decision made once, with the assignment visible in the portal, rather
than something a seeding script does because it can.

The seeded environment does include a role-assignable group, so if you want to exercise an
assignment path you have somewhere sensible to point it, deliberately.

Two things about custom roles are worth knowing. `isEnabled` set to false makes a definition that
exists and cannot be assigned, which is a state reports routinely miss. And `version` is a free
string Entra does not interpret, so anything treating it as a number is guessing.

## EXAMPLES

### Example 1: Creates the three custom role definitions, and assigns none of them

```powershell
New-EntraDirectoryRole
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates only the group reader role

```powershell
New-EntraDirectoryRole -RoleKey role-groupreader -PassThru
```

Output: The role definition, with its resource actions.

Use case: Testing an eligibility report against a single custom role.

### Example 3: Previews the role definitions

```powershell
New-EntraDirectoryRole -WhatIf
```

Output: One WhatIf line per role.

Use case: Reviewing the actions each role grants before they exist in a tenant.

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

Returns the created role definitions

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

### -RoleKey

Creates only the named roles, by their Key column. Defaults to all of them.

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

### EntraDirectoryRole

One object per role definition created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraRoleEligibility]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
