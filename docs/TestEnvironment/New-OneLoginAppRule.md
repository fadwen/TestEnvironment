---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginAppRule.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginAppRule
---

# New-OneLoginAppRule

## SYNOPSIS

Creates the seeded app rules, which hand a seeded app's groups claim out by seeded role

## SYNTAX

### __AllParameterSets

```
New-OneLoginAppRule [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An app rule decides what an app hands a person when they sign in, by condition, so what a token carries depends on rules as well as on grants. Two are seeded:

- Directory groups for staff, on Expenses Web, enabled: anybody in All Staff gets their directory group names in the groups claim, so the claim changes when group membership does.
- Groups for everyone outside Finance, on Payroll Console, disabled: it would hand the payroll app every group of everyone who is not in Finance if anybody enabled it, the dormant rule an access review has to find.

A rule goes only on a proved seeded app and names only a role the seed may use. A rule naming somebody else's role would give the people holding it a claim on a seeded app; a rule on somebody else's app would change what that app gives its real users. The action is fixed by the provider, not taken from the data: set the groups claim from member_of, which on a seeded person names seeded groups in the lab domain and nothing else. There is no parameter for either.

A rule whose app or role the tiers being seeded do not create is skipped rather than created against nothing. Teardown proves a rule by the seeded app it sits on and the prefix on its name, and removes it with the app unless the app is kept.

## EXAMPLES

### Example 1: Create both seeded rules

```powershell
New-OneLoginAppRule
```

DESCRIPTION: Creates the enabled rule on Expenses Web and the disabled one on Payroll Console
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, once the apps and roles exist

### Example 2: Create the dormant rule alone

```powershell
New-OneLoginAppRule -Key payroll-dormant -PassThru
```

DESCRIPTION: Creates the disabled rule on Payroll Console
OUTPUT: A result object naming it
USE CASE: Testing whether a review of app rules reports a disabled one

### Example 3: Read the rules back

```powershell
Get-TestEnvironmentReport -PassThru | Select-Object -ExpandProperty AppRules
```

DESCRIPTION: Lists the seeded rules with their app and whether each is enabled
OUTPUT: One row per rule
USE CASE: Confirming each rule sits on a seeded app

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

### -Key

Create only the rows with these keys, from the seed data file. All of them by default.

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

Return a result object describing what was created, reused and refused.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

Create only the rules whose role the chosen tiers create. Both tiers by default.

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

Only when -PassThru is supplied: a summary with TotalAppRules, CreatedAppRules, ReusedAppRules, SkippedAppRules, AppRules and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginApp]()
- [New-OneLoginRole]()

