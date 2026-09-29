---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginSelfRegistration.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginSelfRegistration
---

# New-OneLoginSelfRegistration

## SYNOPSIS

Creates the seeded self-registration profile, always disabled, moderated and open to the lab domain only

## SYNTAX

### __AllParameterSets

```
New-OneLoginSelfRegistration [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A self-registration profile is a public page where anybody can create themselves an account, so enabling one is a single click that changes who can get in. One is seeded, Partner Sign-up, for an access review to find.

It is created in the one shape that cannot admit anybody, and none of it has a parameter:

- Disabled, so there is no public page.
- Moderated, so even enabled it admits nobody until an administrator approves them.
- Open only to the lab email domain, under example.com by default, which RFC 2606 reserves, so no real address can register.
- With no default role and no default group, so a registrant could never land in anything.

A re-run puts that shape back if anybody loosened it. The help text carries the seed tag inside a sentence, and teardown requires that tag and the prefix on the name together; a prefixed profile without the tag is left alone.

## EXAMPLES

### Example 1: Create the seeded profile

```powershell
New-OneLoginSelfRegistration
```

DESCRIPTION: Creates Partner Sign-up, disabled and moderated
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment

### Example 2: Put the safe shape back

```powershell
New-OneLoginSelfRegistration -PassThru
```

DESCRIPTION: Reuses the profile and disables and restricts it again if it was loosened
OUTPUT: A result object; Restored is 1 when it had been changed
USE CASE: Repairing the seed after somebody enabled the page

### Example 3: Preview in an account you care about

```powershell
New-OneLoginSelfRegistration -WhatIf
```

DESCRIPTION: Shows the profile that would be created, creating none
OUTPUT: A What if: line
USE CASE: Checking the name does not collide with a real profile

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

Create only the rows with these keys, from the seed data file. All of them by default.

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

Only when -PassThru is supplied: a summary with TotalSelfRegistrations, CreatedSelfRegistrations, ReusedSelfRegistrations, Restored, SelfRegistrations and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginUser]()
- [Test-TestEnvironment]()

