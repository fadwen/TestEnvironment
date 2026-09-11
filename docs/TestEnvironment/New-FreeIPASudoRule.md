---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPASudoRule
---

# New-FreeIPASudoRule

## SYNOPSIS

Creates the seeded sudo commands, command groups and rules from Data\FreeIPASudoCommands.csv and Data\FreeIPASudoRules.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPASudoRule [[-RuleName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Sudo rules are FreeIPA's answer to who may run what as whom, and the seed builds them in the shapes
a sudo review exists to surface. Eight commands and four command groups first, one of them holding
only editors that escape to a shell; then seven rules: a grant through a non-POSIX group three
levels down the chain that runs as root without a password, a client run as a local account that is
not an IPA user, a host category of all with one command, a disabled rule for a disabled user
granting everything, the editors granted to contractors without a password, an allow and a deny in
one rule, and a rule bound to nothing.

A sudo command is named by its path and cannot carry the prefix. It is created with the seed marker
in its description, and a command that already exists in the realm without the marker is reused as
it is: the rule that names it is ours, the command is not, and teardown leaves it behind. Command
groups and rules carry the prefix and the marker like everything else.

A rule's who, where, what, run-as and options are added after the rule exists, one call per clause.
A run-as user that is not an IPA user, such as root or postgres, is what FreeIPA stores as an
external run-as user, and the rule sends it as written.

## EXAMPLES

### Example 1: Creates every seeded sudo command, command group and rule

```powershell
New-FreeIPASudoRule
```

Output: None

Use case: Called by New-FreeIPAEnvironment once users, groups, hosts and host groups exist

### Example 2: Rebuilds the shell-escape rule alone

```powershell
New-FreeIPASudoRule -RuleName contractor-editors -PassThru
```

Output: The result object with one rule

Use case: Testing a review that flags an editor granted without a password

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPASudoRule -WhatIf
```

Output: One WhatIf line per command, group and rule

Use case: Seeing which command paths already exist in the realm before seeding

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

Creates only the named rules, by their Name column, and every command and command group. Defaults to
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

Only when -PassThru is supplied: TotalRules, CreatedRules, UpdatedRules, CommandsCreated, CommandsReused, CommandGroupsCreated, MembershipsApplied, one entry per rule under Rules with its CSV key, name, order and whether it is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHbacRule]()
- [New-FreeIPAHostgroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
