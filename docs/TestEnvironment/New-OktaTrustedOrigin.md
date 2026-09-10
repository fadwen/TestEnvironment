---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaTrustedOrigin.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaTrustedOrigin
---

# New-OktaTrustedOrigin

## SYNOPSIS

Creates the seeded trusted origins

## SYNTAX

### __AllParameterSets

```
New-OktaTrustedOrigin [[-OriginName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A trusted origin is an allowlist entry: a URL Okta will accept cross-origin calls from (CORS), or
redirect a browser back to after sign-in or sign-out (REDIRECT). They are cheap, they are
security-relevant, and a fresh org has none - so any script that audits them has nothing to find
until these exist.

The two seeded entries differ in scope on purpose. One carries both CORS and REDIRECT, the other
only CORS. A report that assumes every origin does both, or that flattens the scope list to a single
value, gets the second one wrong.

The origins are under example.com, which is IANA-reserved. That matters more here than elsewhere: a
trusted origin naming a domain somebody else controls is an actual security finding, not just untidy
test data.

## EXAMPLES

### Example 1: Creates every trusted origin and returns the results

```powershell
New-OktaTrustedOrigin -PassThru
```

### Example 2: Creates only the portal origin

```powershell
New-OktaTrustedOrigin -OriginName Lab-Portal -PassThru
```

Output: The origin, with its CORS and redirect scopes.

Use case: Seeding the origin a sign-in widget test embeds from.

### Example 3: Previews every origin

```powershell
New-OktaTrustedOrigin -WhatIf
```

Output: One WhatIf line per origin.

Use case: Reviewing the URLs before they are trusted by the org.

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

### -OriginName

Restrict the operation to these CSV origin names

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

Return the detailed result object

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

Only when -PassThru is supplied: a summary with TotalOrigins, CreatedOrigins, ExistingOrigins, Origins and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

## RELATED LINKS

- [New-OktaEventHook]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
