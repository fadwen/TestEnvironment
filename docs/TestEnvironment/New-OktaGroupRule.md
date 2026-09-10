---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaGroupRule.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaGroupRule
---

# New-OktaGroupRule

## SYNOPSIS

Creates the group rules that populate the automatic groups

## SYNTAX

### __AllParameterSets

```
New-OktaGroupRule [[-RuleName] <string[]>] [-SkipActivation] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Group rules are Okta's answer to dynamic membership: an expression over the user profile, evaluated
by Okta, that maintains a group without anybody assigning anyone. Since Okta groups cannot nest,
rules are the closest it gets to structural membership, and they are worth having in a lab because
they fail in ways direct assignment does not.

Three rules ship, each reading a different kind of attribute:

- a boolean custom attribute (labIsContractor)
- an enumerated custom attribute (labClearanceLevel)
- a base attribute through an expression function (department)

Two behaviours are worth knowing, both confirmed against a real tenant rather than assumed:

- Rules are evaluated against staged and suspended users, not only active ones.
The
  contractor rule picks up both seeded contractors even though one has never been
  activated and the other is suspended.
That is worth knowing because it is the
  opposite of what "only active users are in scope" would suggest, and it means a
  rule granting an entitlement reaches accounts nobody has signed into.
- Rules apply asynchronously.
Membership appears a short while after activation rather
  than immediately, so a report run straight afterwards can understate it.

## EXAMPLES

### Example 1: Creates and activates every group rule

```powershell
New-OktaGroupRule
```

### Example 2: Creates the rules inactive, so you can watch membership appear when you activate them

```powershell
New-OktaGroupRule -SkipActivation -PassThru
```

### Example 3: Previews two rules without creating them

```powershell
New-OktaGroupRule -RuleName Contractors, Engineering -WhatIf
```

Output: One WhatIf line per rule, with its expression and target group.

Use case: Reviewing an expression before it starts moving real users, on an org where the seeded
groups sit beside real ones.

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

### -RuleName

Restrict the operation to these CSV rule names. The prefix is added automatically.

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

### -SkipActivation

Create the rules but leave them inactive. An inactive rule assigns nobody, which is a useful state
to test a compliance report against.

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

Only when -PassThru is supplied: a summary with TotalRules, CreatedRules, UpdatedRules, ActivatedRules, Rules and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

The target groups must exist first, so run New-OktaGroup before this.

## RELATED LINKS

- [New-OktaGroup]()
- [New-OktaUser]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
