---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOnePopulation.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOnePopulation
---

# New-PingOnePopulation

## SYNOPSIS

Creates the seeded populations, which are what teardown asks rather than guessing from names

## SYNTAX

### __AllParameterSets

```
New-PingOnePopulation [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A population is PingOne's container for people.
A user belongs to exactly one,
which makes it the thing teardown can ask: rather than matching names and hoping, it
enumerates the populations this module created and deletes what is in them.

That is the stronger half of the ownership story.
The weaker half, the seed tag in a
custom attribute, exists for the user who has been moved out of a seeded population by
hand and would otherwise become unownable.

**No seeded population is ever the environment's default, and there is no parameter
that would make one.** The default is where every user created without a population
lands, including users nothing to do with this module, so changing it is a change to
how the environment behaves rather than to the data in it.
A test under
Tests/Unit/Providers/PingOne asserts that, so adding a -Default switch as a convenience
is caught as the regression it would be.

Re-running is safe: a population that already exists is reused rather than duplicated,
which is what makes a partial run resumable.

## EXAMPLES

### EXAMPLE 1

New-PingOnePopulation

DESCRIPTION: Creates every seeded population
OUTPUT: None
USE CASE: Run for you as the second step of New-TestEnvironment

### EXAMPLE 2

New-PingOnePopulation -Key staff -PassThru

DESCRIPTION: Creates one population and reports what happened
OUTPUT: A result object naming it and its id
USE CASE: Rebuilding a container that was deleted by hand

### EXAMPLE 3

New-PingOnePopulation -WhatIf

DESCRIPTION: Lists the populations it would create
OUTPUT: One What if line per population, and nothing created
USE CASE: Checking the population names against an environment before seeding it

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

Create only the named populations.
All of them by default.

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

Return a result object describing what was created.

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

Only when -PassThru is supplied: a summary with TotalPopulations, CreatedPopulations, ReusedPopulations, Populations and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOneUser
Remove-PingOneEnvironment]()
