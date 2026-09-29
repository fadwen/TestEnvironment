---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginMfaFactor.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginMfaFactor
---

# New-OneLoginMfaFactor

## SYNOPSIS

Pre-enrols the seeded people's MFA factors, where the account already offers the factor

## SYNTAX

### __AllParameterSets

```
New-OneLoginMfaFactor [[-Username] <string[]>] [[-Tier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Three Core people - awhitfield, praghunathan and talvarez - are given an email factor in the seed data, so a report of who has MFA has somebody to find and a larger number of people without it.

A factor is enrolled only where the account already offers it to that person. Whether a factor is offered is an account-wide setting, and turning one on would change what every real person is asked for at sign-in, so the seed never does; in an account that offers none, as a trial does, every person is reported as skipped and nothing is sent.

A factor is enrolled on proved seeded people only, and only ever as already verified, so no code or message is sent to anybody - and every seeded address is at the lab domain, which cannot receive one. A person who already holds a factor of that name keeps it.

Teardown removes factors with the people who hold them.

## EXAMPLES

### Example 1: Enrol every seeded factor

```powershell
New-OneLoginMfaFactor
```

DESCRIPTION: Enrols the email factor on the three people the data gives one, where the account offers it
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, as the last step

### Example 2: See whether the account offers the factor

```powershell
New-OneLoginMfaFactor -PassThru | Select-Object EnrolledFactors, Skipped
```

DESCRIPTION: Attempts the enrolments and shows what happened
OUTPUT: The number enrolled, and the people skipped because the account offers no such factor
USE CASE: Deciding whether to turn a factor on in a lab account before seeding again

### Example 3: Enrol one person

```powershell
New-OneLoginMfaFactor -Username talvarez -PassThru
```

DESCRIPTION: Enrols talvarez alone
OUTPUT: A result object naming the factor, or the reason it was skipped
USE CASE: Testing a report against a single person with MFA

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

### -Tier

Enrol only the Core people or only the Bulk people. Both by default; only Core people are given a factor.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Username

Enrol only the people with these keys from the seed data - the username without the prefix, such as talvarez. Everybody the data gives a factor by default.

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

Only when -PassThru is supplied: a summary with TotalFactors, EnrolledFactors, ExistingFactors, Skipped, Factors and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginUser]()
- [Get-TestEnvironmentReport]()

