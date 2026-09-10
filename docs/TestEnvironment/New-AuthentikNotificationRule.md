---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikNotificationRule
---

# New-AuthentikNotificationRule

## SYNOPSIS

Creates the seeded notification rules and the webhook transports they deliver to

## SYNTAX

### __AllParameterSets

```
New-AuthentikNotificationRule [[-RuleName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates two notification rules from Data\AuthentikNotificationRules.csv, each with a webhook
transport of its own: a warning-level rule and an alert-level rule with send-once set. The webhooks
point at a host that answers nothing, which is deliberate: the objects exist for an inventory to
find, and a delivery that fails is a truer shape than one that was never attempted.

A rule references its transports by primary key, so the transport is created first and reused on a
re-run. Neither type has attributes or a description, so the seed prefix on the name is the
ownership evidence for both.

## EXAMPLES

### Example 1: Creates both rules and their transports

```powershell
New-AuthentikNotificationRule
```

Output: None

Use case: Called by New-AuthentikEnvironment as its last step

### Example 2: Creates only the alert rule

```powershell
New-AuthentikNotificationRule -RuleName 'Alert Relay' -PassThru
```

Output: The rule, its severity and its transport

Use case: Testing a report that has to show the send-once flag

### Example 3: Lists the rules and transports that would be created

```powershell
New-AuthentikNotificationRule -WhatIf
```

Output: One WhatIf line per object

Use case: Checking the webhook URLs before anything can try to deliver to them

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

Only when -PassThru is supplied: TotalRules, CreatedRules, UpdatedRules, TransportsCreated, one entry per rule under Rules with its primary key, name, severity and transport, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
