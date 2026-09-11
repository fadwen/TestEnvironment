---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAOtpToken
---

# New-FreeIPAOtpToken

## SYNOPSIS

Creates the seeded OTP tokens from Data\FreeIPAOtpTokens.csv on their users

## SYNTAX

### __AllParameterSets

```
New-FreeIPAOtpToken [[-TokenId] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

FreeIPA lets an administrator enrol a token on another user's behalf, which is what makes
second-factor state seedable at all. The seed creates four: a time-based token that satisfies one
user's OTP-only authentication type, a counter-based hardware token with a vendor and model, a
disabled token on the disabled account, and an enabled eight-digit token that expired yesterday. The
user whose authentication type also demands a token and who has none stays that way on purpose.

The token secret the realm mints is never read back, kept or returned; the QR code is suppressed. A
re-run modifies what a token can change - description, state, expiry, vendor and model - and leaves
the type, algorithm and digits, which FreeIPA fixes at creation.

Every token carries the seed prefix on its identifier and the seed marker at the end of its
description, which together are what teardown proves ownership by.

## EXAMPLES

### Example 1: Creates every seeded token

```powershell
New-FreeIPAOtpToken
```

Output: None

Use case: Called by New-FreeIPAEnvironment once the users exist

### Example 2: Rebuilds the token that expired yesterday

```powershell
New-FreeIPAOtpToken -TokenId mbell-expired -PassThru
```

Output: The result object with one token

Use case: Testing a report that reads token expiry

### Example 3: Lists the tokens that would be created without creating them

```powershell
New-FreeIPAOtpToken -WhatIf
```

Output: One WhatIf line per token

Use case: Confirming the owners before seeding a shared realm

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

### -TokenId

Creates only the named tokens, by their Id column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalTokens, CreatedTokens, UpdatedTokens, one entry per token under Tokens with its CSV key, identifier, owner, type and whether it is enabled or expired, and Errors. The token secret is never in it. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
