---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginCustomAttribute.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginCustomAttribute
---

# New-OneLoginCustomAttribute

## SYNOPSIS

Creates the custom user fields the seed needs, including its ownership marker

## SYNTAX

### __AllParameterSets

```
New-OneLoginCustomAttribute [[-Shortname] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A OneLogin user has no description field and nothing else that is free text nobody writes: comment, company, department and title are all things an administrator fills in. So the seed creates a custom user field of its own, zztest_seed_tag, writes ZZ-TEST-seed into it on every person it makes, and teardown proves a person is seeded by that value together with the prefix on the username. The field is removed last at teardown, after every person who carries it.

The other fields are there because they are awkward in the ways scripts get wrong:

- zztest_badge_id is empty on some people, so a report has to cope with a field that is simply absent.
- zztest_contractor is a boolean stored as text, because OneLogin custom fields are text. The string false is not falsy in PowerShell, so anything casting it rather than comparing it reads every person as a contractor.
- zztest_cost_center is shared by whole departments, which a mapping or a report can group on.

Every shortname starts with zztest_. A field has no description, so the shortname is the only part of it the seed controls, and teardown removes a field only when the seed data declares it and its shortname carries that prefix. Shortnames take letters, digits and underscores only; OneLogin refuses a dash as invalid.

Re-running is safe: a field that already exists is reused and never replaced, because replacing it would drop the value every seeded person holds in it.

## EXAMPLES

### Example 1: Create every seeded field

```powershell
New-OneLoginCustomAttribute
```

DESCRIPTION: Creates the seed tag field and the three lab fields
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, before anybody is created

### Example 2: Create the ownership marker alone

```powershell
New-OneLoginCustomAttribute -Shortname zztest_seed_tag -PassThru
```

DESCRIPTION: Creates only the field every seeded person is tagged in
OUTPUT: A result object naming it and its id
USE CASE: Preparing an account before seeding people by hand

### Example 3: Preview in an account you care about

```powershell
New-OneLoginCustomAttribute -WhatIf
```

DESCRIPTION: Shows every field that would be created, creating none
OUTPUT: A What if: line per field
USE CASE: Checking what the seed adds to a production account's schema

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

### -Shortname

Create only the fields with these shortnames. All of them by default.

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

Only when -PassThru is supplied: a summary with TotalAttributes, CreatedAttributes, ReusedAttributes, Attributes and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginUser]()
- [Connect-TestEnvironment]()

