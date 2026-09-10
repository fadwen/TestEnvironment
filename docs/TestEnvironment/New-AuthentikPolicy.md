---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikPolicy
---

# New-AuthentikPolicy

## SYNOPSIS

Creates the seeded expression policies and binds them to the seeded applications

## SYNTAX

### __AllParameterSets

```
New-AuthentikPolicy [[-PolicyName] <string[]>] [-SkipBinding] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three expression policies from Data\AuthentikPolicies.csv and binds each to an application:
one that denies anyone carrying the contractor attribute, one that admits only the finance
department by group membership, and a business-hours policy bound but disabled, so a report has to
tell bound from enforced.

A policy in Authentik is only an expression until a binding attaches it to a target, and the target
of an application binding is the application's policy-binding-model UUID rather than its own primary
key. That is resolved from the seeded applications by slug, so the CSV names its target by the same
Slug column the applications file uses. An expression that refers to a seeded group writes {prefix}
where the prefix goes, and a literal `n where a line break goes, because a CSV cell cannot hold
either as typed.

Policies have no attributes and no description, so the seed prefix on the name is the only evidence
of ownership they can carry.

## EXAMPLES

### Example 1: Creates every seeded policy and its binding

```powershell
New-AuthentikPolicy
```

Output: None

Use case: Called by New-AuthentikEnvironment after the applications step

### Example 2: Creates only the contractor policy, bound to payroll

```powershell
New-AuthentikPolicy -PolicyName 'Deny Contractors' -PassThru
```

Output: The policy with its binding's order and enabled flag

Use case: Testing an access report against a single denial

### Example 3: Lists the policies that would be created, bound to nothing

```powershell
New-AuthentikPolicy -SkipBinding -WhatIf
```

Output: One WhatIf line per policy

Use case: Reviewing the expressions before they govern anything

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

### -PolicyName

Creates only the named policies, by their Name column. Defaults to all of them.

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

### -SkipBinding

Creates the policies without binding them to anything.

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

Only when -PassThru is supplied: TotalPolicies, CreatedPolicies, UpdatedPolicies, BindingsCreated, one entry per policy under Policies with its primary key, name, the slug it is bound to, its order and whether the binding is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikApplication]()
- [New-AuthentikGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
