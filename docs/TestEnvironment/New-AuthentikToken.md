---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikToken
---

# New-AuthentikToken

## SYNOPSIS

Creates the seeded user tokens from Data\AuthentikTokens.csv

## SYNTAX

### __AllParameterSets

```
New-AuthentikToken [[-Identifier] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three tokens on seeded users: a non-expiring API key on the reporting service account, an
app password on the most privileged person in the directory with twenty minutes to run, and an app
password on the disabled account that expired a day ago, which is exactly the credential offboarding
misses. A credential audit has all three states to find, and the expired one is the finding a report
that only checks expiring=false gets wrong.

The expiry is written in minutes because an instance caps an app password at its default token
duration, thirty minutes out of the box, and refuses anything longer; an API token's expiry is
assigned by the server whatever is sent, so only the app passwords carry one.

The token's secret is never returned or written anywhere: Authentik hands it out only through its
own view_key endpoint, and nothing in the seed needs it. The identifier carries the slug prefix and
the token belongs to a seeded user, and those two together are the evidence teardown proves
ownership by.

## EXAMPLES

### Example 1: Creates every seeded token

```powershell
New-AuthentikToken
```

Output: None

Use case: Called by New-AuthentikEnvironment after the bindings step

### Example 2: Creates the expired token on the disabled account only

```powershell
New-AuthentikToken -Identifier tomas-stale -PassThru
```

Output: The token object with its expiry a day in the past

Use case: Testing a credential report against the case offboarding leaves behind

### Example 3: Lists the tokens that would be created

```powershell
New-AuthentikToken -WhatIf
```

Output: One WhatIf line per token, naming its user

Use case: Confirming the identifiers before seeding a shared instance

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

### -Identifier

Creates only the named tokens, by their Identifier column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalTokens, CreatedTokens, UpdatedTokens, one entry per token under Tokens with its identifier, CSV key, user, intent, expiry and whether it has already expired, and Errors. No entry carries the secret. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
