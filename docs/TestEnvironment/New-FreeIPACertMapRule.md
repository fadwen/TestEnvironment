---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPACertMapRule
---

# New-FreeIPACertMapRule

## SYNOPSIS

Creates the seeded certificate identity mapping rules from Data\FreeIPACertMapRules.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPACertMapRule [[-RuleName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A certificate mapping rule is how a smart card or client certificate becomes a user: a match rule
says which certificates the rule applies to, and a map rule says how to find the user. The seed
creates two: an enabled rule matching the lab issuing CA and mapping by the certificate data one
seeded user carries, and a disabled rule matching an email address in the certificate's subject
alternative name against the seed domain, substituted for the connected realm's.

A rule whose row says Enabled FALSE is disabled after creation. Every rule carries the seed prefix
on its name and the seed marker at the end of its description.

## EXAMPLES

### Example 1: Creates both seeded rules

```powershell
New-FreeIPACertMapRule
```

Output: None

Use case: Called by New-FreeIPAEnvironment as its last step

### Example 2: Rebuilds the enabled rule

```powershell
New-FreeIPACertMapRule -RuleName lab-smartcard -PassThru
```

Output: The result object with one rule

Use case: Testing a report against the certificate mapping data a seeded user carries

### Example 3: Lists the rules that would be created without creating them

```powershell
New-FreeIPACertMapRule -WhatIf
```

Output: One WhatIf line per rule

Use case: Confirming the match rules before seeding a shared realm

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

### -RuleName

Creates only the named rules, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalRules, CreatedRules, UpdatedRules, one entry per rule under Rules with its CSV key, name, priority and whether it is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
