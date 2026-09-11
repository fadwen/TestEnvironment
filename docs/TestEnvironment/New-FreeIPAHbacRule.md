---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAHbacRule
---

# New-FreeIPAHbacRule

## SYNOPSIS

Creates the seeded HBAC services, service groups and rules from Data\FreeIPAHbacServices.csv and Data\FreeIPAHbacRules.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPAHbacRule [[-RuleName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Host-based access control is FreeIPA's answer to who may log in where, and the seed builds it in the
shapes a review has to handle. Three custom PAM services and three service groups first, one of them
mixing the stock sshd and login with a seeded service; then seven rules: an ordinary grant from a
group to two host groups for a service group, the broadest grant through the root of the nesting
chain to a host that demands a second factor, a user admitted twice by name and by group,
contractors confined to one host's console, an allow-everything rule that is switched off, a rule
bound to nothing, and a disabled user still named in a live rule.

A rule's who, where and what are added after the rule exists, one call per clause, and a rule whose
row says a category of 'all' carries no members of that kind. A rule whose row says Enabled FALSE is
disabled after it is created, and enabled again on a re-run if its row changed back.

Nothing here ever names a rule the realm shipped with. allow_all, allow_systemd-user and anything
else without the seed prefix are never created, modified, enabled or disabled, and the test suite
pins that no request reaches one. A stock service such as sshd may be a member of a seeded rule or
service group, which changes nothing about the service.

## EXAMPLES

### Example 1: Creates every seeded HBAC service, service group and rule

```powershell
New-FreeIPAHbacRule
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, groups, hosts and host groups exist

### Example 2: Rebuilds the rule with the double grant

```powershell
New-FreeIPAHbacRule -RuleName finance-payroll -PassThru
```

Output: The result object with one rule

Use case: Testing a report that counts grants against a rule of known shape

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPAHbacRule -WhatIf
```

Output: One WhatIf line per service, group and rule

Use case: Confirming the prefix before seeding a shared realm

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

Creates only the named rules, by their Name column, and every service and service group. Defaults to
all of them.

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

Only when -PassThru is supplied: TotalRules, CreatedRules, UpdatedRules, ServicesCreated, ServiceGroupsCreated, MembershipsApplied, one entry per rule under Rules with its CSV key, name and whether it is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPASudoRule]()
- [New-FreeIPAHostgroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
