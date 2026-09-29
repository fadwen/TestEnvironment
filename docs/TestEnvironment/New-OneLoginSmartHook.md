---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginSmartHook.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginSmartHook
---

# New-OneLoginSmartHook

## SYNOPSIS

Creates the seeded Smart Hook, always disabled and gated on a seeded role

## SYNTAX

### __AllParameterSets

```
New-OneLoginSmartHook [[-Key] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A Smart Hook is code OneLogin runs during a sign-in, so it belongs in any review of what can change how people sign in. One is seeded: a pre-authentication hook, whose handler changes nothing - it hands back the policy the person already has.

What keeps it from reaching anybody real, none of which has a parameter:

- It is created disabled, and a re-run disables it again if somebody enabled it.
- It carries one condition, membership of the seeded Contractors role, so even enabled it would run for seeded people and nobody else.
- The first line of its code is the marker "// Seeded by TestEnvironment. Safe to delete. [ZZ-TEST-seed]". A hook has no name or description, so that line is what teardown proves it by, together with conditions that name only seeded roles.

OneLogin allows one hook of each type in an account. An account that already has its own pre-authentication hook keeps it untouched: OneLogin refuses the seed's create, and the step reports the refusal and suggests -Skip Hooks. A hook whose role the tiers being seeded do not create is skipped. The code runs on the nodejs22.x runtime.

## EXAMPLES

### Example 1: Create the seeded hook

```powershell
New-OneLoginSmartHook
```

DESCRIPTION: Creates the disabled pre-authentication hook gated on Contractors
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, once the roles exist

### Example 2: Make sure it is off

```powershell
New-OneLoginSmartHook -PassThru
```

DESCRIPTION: Reuses the seeded hook and disables it again if it was enabled
OUTPUT: A result object; DisabledAgain is 1 when it had been turned on
USE CASE: Putting the seed back after somebody experimented in the portal

### Example 3: Preview in an account you care about

```powershell
New-OneLoginSmartHook -WhatIf
```

DESCRIPTION: Shows the hook that would be created, creating none
OUTPUT: A What if: line
USE CASE: Checking whether the account already has a hook of that type

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

Create the hook only when the chosen tiers create the role it is gated on. Both tiers by default.

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

Only when -PassThru is supplied: a summary with TotalHooks, CreatedHooks, ReusedHooks, SkippedHooks, DisabledAgain, Hooks and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginRole]()
- [Remove-TestEnvironment]()

