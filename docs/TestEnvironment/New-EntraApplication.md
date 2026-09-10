---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraApplication.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraApplication
---

# New-EntraApplication

## SYNOPSIS

Creates the seeded app registrations, their service principals and their assignments

## SYNTAX

### __AllParameterSets

```
New-EntraApplication [[-ApplicationKey] <string[]>] [-SkipAssignment] [-ShowProgress] [-PassThru]
 [-WhatIf] [-Confirm]
```

## DESCRIPTION

Users and groups answer who exists. Applications are what turn that into who has access to what,
which is the question most scripts written against Entra are actually trying to report on, and the
one that is not reproducible without them.

Six applications are created, and the interesting ones are the middle three. One app is assigned to
a group only, one to a user only, and one to both a group and a user who is already in that group.
That last pair is the most common access-review bug there is: Marcus is assigned to the Payroll
Console directly and belongs to no group that has it, so a report that expands group assignments and
stops there misses him entirely, while Priya is assigned both ways and gets counted twice by a naive
union.

The application and the service principal are deliberately kept distinct, including one application
created with no service principal at all. They are two objects and people conflate them constantly -
the registration is the definition, the service principal is the instance of it in this tenant that
assignments and sign-ins actually attach to. An app with no service principal cannot be signed into
and does not appear in enterprise applications, which is exactly what it looks like when consent has
never been granted.

Creating the service principal is retried, because it fails on first attempt more often than not.
Verified against a live tenant: POST /servicePrincipals for an application created moments earlier
returns "The appId does not reference a valid application object" - which reads like a wrong id and
is really replication lag.

App role assignments use the default access role, an all-zero GUID. That is how Entra represents
"assigned to the application without a specific role" and it is what the portal creates when an app
defines no roles of its own.

## EXAMPLES

### Example 1: Creates all six applications, five service principals and their assignments

```powershell
New-EntraApplication
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates just the application with a direct assignee and no group

```powershell
New-EntraApplication -ApplicationKey app-direct-only -PassThru
```

Output: The application object

Use case: Reproducing the access report that misses directly-assigned users

### Example 3: Creates two applications without their assignments

```powershell
New-EntraApplication -ApplicationKey app-groups-only, app-unassigned -SkipAssignment -PassThru
```

Output: The two application objects.

Use case: Testing an assignment script of your own against apps that start empty.

## PARAMETERS

### -ApplicationKey

Creates only the named applications, by their Key column. Defaults to all of them.

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

Returns the created applications

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

### -SkipAssignment

Creates the applications and service principals but assigns nobody

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

### EntraApplication

One object per application created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraGroup]()
- [New-EntraUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
