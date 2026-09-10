---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaPolicy.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaPolicy
---

# New-OktaPolicy

## SYNOPSIS

Creates the seeded sign-on and password policies, with their rules

## SYNTAX

### __AllParameterSets

```
New-OktaPolicy [[-PolicyName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Policies are where an identity environment stops being a list of objects and starts having
behaviour. Three are created, chosen so that precedence and scoping are both observable:

- Admin-Session, scoped to the administrators group, whose rule only permits sign-in
  from the Corporate-Egress network zone.
- Standard-Session, scoped to everyone, allowing sign-in from anywhere with a longer
  session.
Two overlapping sign-on policies is the interesting part: a user in both
  groups is governed by the higher-priority one, and a report that lists policies
  without their order tells you nothing about what actually applies.
- Contractor-Password, scoped to the rule-driven contractors group, with a longer
  minimum length and a shorter maximum age than the org default.

Okta assigns priority by creation order, newest first, so the order of the CSV rows is the order of
precedence. That is worth knowing before wondering why a policy seems to be ignored.

Password policies carry their settings on the policy itself. Sign-on policies carry almost nothing
useful until a rule is added, which is why each sign-on row here also defines one - a sign-on policy
with no rules is inert, and inert-but-present is a confusing thing to find in a lab.

## EXAMPLES

### Example 1: Creates every policy and its rules, returning the results

```powershell
New-OktaPolicy -PassThru
```

### Example 2: Previews one policy without creating it

```powershell
New-OktaPolicy -PolicyName Admin-Session -WhatIf
```

### Example 3: Creates only the password policy

```powershell
New-OktaPolicy -PolicyName Contractor-Password -PassThru
```

Output: The policy and its rule.

Use case: Testing a password-policy report without creating the sign-on policies, which govern real
sign-in behaviour for the groups they name.

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

Return the detailed result object

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

Restrict the operation to these CSV policy names

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

Only when -PassThru is supplied: a summary with TotalPolicies, CreatedPolicies, ExistingPolicies, RulesCreated, Policies and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Needs the groups it scopes to and the zones its rules reference, so run
New-OktaGroup and New-OktaNetworkZone first.

These policies govern real sign-in behaviour for the groups they name.
On a shared
tenant that is not a hypothetical: an admin who is only in the administrators group and
is not on a listed IP range will be denied.

## RELATED LINKS

- [New-OktaNetworkZone]()
- [New-OktaGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
