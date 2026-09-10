---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraRoleEligibility.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraRoleEligibility
---

# New-EntraRoleEligibility

## SYNOPSIS

Makes seeded principals *eligible* for the seeded custom roles, and never active in them

## SYNTAX

### __AllParameterSets

```
New-EntraRoleEligibility [[-EligibilityKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

New-EntraDirectoryRole creates three custom role definitions and assigns none of them, because an
active assignment is a privilege grant and a seeding script should not be making one. This function
does not change that rule. It creates **eligible** schedules through Privileged Identity Management,
and an eligible schedule grants nothing at all until a human signs in and activates it.

That is the same bargain the Conditional Access policies strike. A report-only policy is fully
evaluated and fully logged and denies nothing; an eligible role assignment is fully visible to every
privilege report and confers nothing. Both are the whole value for none of the risk, and in both
cases **the state is not a parameter** - there is no -Active, no -AssignmentType and no -Permanent,
and a contract test asserts their absence.

What this exists to break:

- `GET /roleManagement/directory/roleAssignments` returns **nothing** for these roles.
  A standing-privilege report that reads that endpoint and stops - which is most of them -
  concludes the custom roles are held by nobody, while three principals are one click from
  holding them.
The absence is the finding.
- **elig-userwriter-au** is scoped to an administrative unit, not the directory.
Its
  directoryScopeId is /administrativeUnits/{id} rather than /, so the write it grants
  reaches only seeded users.
Anything that reads roleDefinitionId and ignores
  directoryScopeId reports it as tenant-wide, which is the wrong answer in the
  direction that matters.
- **elig-appreader-group** is held by a role-assignable group rather than a person, so
  the humans who can actually activate it are one membership expansion away and a report
  listing principals shows a group name in a column it formats as a user.

Three safety properties, none of them configurable:

1.
**Only seeded custom roles.** The role is resolved through Get-EntraSeededObject,
   which returns custom definitions carrying the seed prefix and refuses built-ins.
A row
   naming a role that does not resolve that way is skipped rather than guessed at, so
   there is no path from this data to eligibility for Global Administrator.
2.
**Only seeded principals**, resolved the same way every other reference in this module
   is.
3.
**The eligibility expires on its own.** Each schedule is created with an
   afterDuration expiry rather than noExpiration, so a lab nobody ever tore down stops
   granting the option to activate after thirty days.

Privileged Identity Management needs Entra ID P2. Without it the create is refused, and this reports
that plainly rather than failing in a way that reads like a bug.

## EXAMPLES

### Example 1: Makes the three seeded principals eligible for the three seeded custom roles

```powershell
New-EntraRoleEligibility
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates them and shows which principal is eligible for what, at which scope

```powershell
New-EntraRoleEligibility -PassThru | Format-Table Role, Principal, Scope
```

Output: One row per eligibility

Use case: Confirming the scope differences the report is meant to expose

### Example 3: Creates only the group-scoped eligibility

```powershell
New-EntraRoleEligibility -EligibilityKey elig-appreader-group -PassThru
```

Output: The eligibility, showing a group rather than a user as the principal.

Use case: Reproducing the case where a role report has to expand a group to find who is eligible.
The eligibility is eligible and never active; there is no parameter that changes that.

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

### -EligibilityKey

Creates only the named eligibilities, by their Key column. Defaults to all of them.

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

Returns the created eligibility schedules

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

### EntraRoleEligibility

One object per eligibility created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraDirectoryRole]()
- [New-EntraGroup]()
- [New-EntraUser]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
