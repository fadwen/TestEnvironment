---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAPasswordPolicy
---

# New-FreeIPAPasswordPolicy

## SYNOPSIS

Creates the seeded password policies from Data\FreeIPAPasswordPolicies.csv, one per seeded group

## SYNTAX

### __AllParameterSets

```
New-FreeIPAPasswordPolicy [[-GroupName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A FreeIPA password policy is attached to a group and ranked by priority, and the lowest number wins
for a user in more than one. The seed creates three: the tightest one on the lab administrators, a
short-lived one with a quick lockout and grace logins on the contractors, and one on the sales
department that never expires a password, never locks anyone out and allows unlimited grace logins,
which is the weakest policy an audit should flag.

A policy is keyed by its group, so it carries no name of its own and no description; it is ours
because its group is. The realm's global policy is never read or written, and the seed data test
pins that no row names it.

The policies are created after the users, so the passwords the users step set were judged by the
global policy alone. Setting a policy afterwards changes what the next password change has to
satisfy, which is the state a report has to describe.

## EXAMPLES

### Example 1: Creates every seeded password policy

```powershell
New-FreeIPAPasswordPolicy
```

Output: None

Use case: Called by New-FreeIPAEnvironment once the groups exist

### Example 2: Rebuilds the policy that never expires a password

```powershell
New-FreeIPAPasswordPolicy -GroupName dept-sales -PassThru
```

Output: The result object with one policy

Use case: Testing a policy review against a known weak policy

### Example 3: Lists the policies that would be created without creating them

```powershell
New-FreeIPAPasswordPolicy -WhatIf
```

Output: One WhatIf line per policy

Use case: Confirming which groups gain a policy before seeding a shared realm

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

### -GroupName

Creates only the policies of the named groups, by their Group column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalPolicies, CreatedPolicies, UpdatedPolicies, one entry per policy under Policies with its group key, the group's name in the realm and its priority, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAGroup]()
- [New-FreeIPAUser]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
