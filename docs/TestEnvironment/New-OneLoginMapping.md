---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginMapping.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginMapping
---

# New-OneLoginMapping

## SYNOPSIS

Creates the seeded user mappings, each gated so it can only ever act on seeded people

## SYNTAX

### __AllParameterSets

```
New-OneLoginMapping [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A OneLogin mapping is a rule that changes people who match its conditions, and an enabled one acts on everybody in the account who matches. That is why every mapping this creates carries one more condition than the seed data gives it: the zztest_seed_tag field must equal ZZ-TEST-seed, with match all. Nobody but this module writes that field, so an enabled seeded mapping can act on seeded people and nobody else, which is what makes it safe to seed one into an account real people sign in to. The condition is added by the code, not the data, and there is no parameter to leave it out; a test asserts that there is none.

Every seeded mapping does one thing, add a seeded role. Two are seeded:

- Finance department gets Finance, enabled. It puts a person into Finance whom the data never lists there, so the payroll app's audience is wider than any list of explicit grants says, and verification has to judge role membership on what is missing only.
- Contractors get Engineering, disabled. It would put every contractor into Engineering if anybody enabled it: the dormant rule an access review has to find.

Mappings are created before people, because OneLogin runs an enabled mapping as each person is created; that was verified against a live account.

Teardown proves a mapping by its prefix, the gate, match all, and actions that add only proved seeded roles. A prefixed mapping that already exists without the gate is left alone and reported.

## EXAMPLES

### Example 1: Create both seeded mappings

```powershell
New-OneLoginMapping
```

DESCRIPTION: Creates the enabled Finance mapping and the disabled contractor one, each gated on the seed tag
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, after the roles and before the people

### Example 2: Create the dormant rule alone

```powershell
New-OneLoginMapping -Key contractor-eng -PassThru
```

DESCRIPTION: Creates the disabled mapping that would widen Engineering
OUTPUT: A result object naming it, with Enabled False
USE CASE: Testing whether an access review finds a disabled rule

### Example 3: Read what a seeded mapping really does

```powershell
Get-TestEnvironmentReport -PassThru | Select-Object -ExpandProperty Mappings
```

DESCRIPTION: Lists the seeded mappings with their condition and action counts
OUTPUT: One row per mapping; each has one more condition than the data, the seed-tag gate
USE CASE: Confirming every seeded mapping is gated

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

Create only the mappings whose role the chosen tiers create. Both tiers by default.

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

Only when -PassThru is supplied: a summary with TotalMappings, CreatedMappings, ReusedMappings, SkippedMappings, Mappings and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginRole]()
- [New-OneLoginUser]()

