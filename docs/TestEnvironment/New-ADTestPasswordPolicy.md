---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-AE
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestPasswordPolicy
---

# New-ADTestPasswordPolicy

## SYNOPSIS

Creates the seeded fine-grained password policies from Data\ADPasswordPolicies.csv

## SYNTAX

### __AllParameterSets

```
New-ADTestPasswordPolicy [[-PolicyName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A fine-grained password policy is how a domain says that one group's passwords are governed
differently from the domain default, and it is a standard audit target: the settings are not visible
in the default password policy a report usually reads, and the one that applies to a person is
decided by precedence rather than by membership order. The seed creates three over seeded groups, at
three precedences, so that machinery has something to act on.

The three are shapes a review has to tell apart. The strictest sits at the lowest precedence, so it
wins for anyone who is also in a weaker group. One applies to a privileged group and never expires a
password and never locks the account out. One is the weakest possible: complexity off and reversible
encryption on, the two settings a review should never find enabled anywhere.

A policy object lives in the Password Settings Container, not under the seeded organisational units,
so a recursive delete of those cannot reach it. It is named with the seed prefix and stamped with
the seed tag in `adminDescription`, the same as everything else this provider creates, and teardown
removes it only on the tag.

This is separate from the single policy `New-ADTestEdgeCase -EdgeCase FineGrainedPolicy` creates,
which exists to give one account an imminent expiry.

## EXAMPLES

### Example 1: Creates all three and applies each to its group

```powershell
New-ADTestPasswordPolicy
```

Output: None

Use case: Called by New-ADEnvironment after the groups exist

### Example 2: Rebuilds the weakest policy alone

```powershell
New-ADTestPasswordPolicy -PolicyName contractors -PassThru
```

Output: The result object with one policy

Use case: Testing a report that should flag reversible encryption

### Example 3: Lists what would be created without creating it

```powershell
New-ADTestPasswordPolicy -WhatIf
```

Output: One WhatIf line per policy

Use case: Confirming the precedences before seeding a domain you care about

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

Only when -PassThru is supplied: TotalPolicies, CreatedPolicies, UpdatedPolicies, SubjectsApplied, one entry per policy under Policies with its CSV key, name, precedence and the group it applies to, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-ADTestSecurityGroups]()
- [New-ADTestEdgeCase]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
