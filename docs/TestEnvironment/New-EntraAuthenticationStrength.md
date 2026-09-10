---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraAuthenticationStrength.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraAuthenticationStrength
---

# New-EntraAuthenticationStrength

## SYNOPSIS

Creates custom authentication strength policies

## SYNTAX

### __AllParameterSets

```
New-EntraAuthenticationStrength [[-StrengthKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

An authentication strength is a named set of acceptable credential combinations, and it is a control
shape Okta has no equivalent of: a grant that says not merely "prove it is you" but "prove it this
way".

Three are created, spanning the range that matters for outcome evaluation - one hardware-backed
only, one passwordless, and one deliberately wide.

The permissive one is the interesting one, and it is here because of a real finding from CaOutcome.
**A custom strength is editable.** Widening it weakens every policy that references it, with no
policy document changing at all, so a baseline that watches only Conditional Access policies will
not notice. Seeding one gives that scenario something to catch.

The combination names themselves contain commas - `password,sms` is one combination, not two - which
is why the seed data separates them with semicolons. Splitting on the wrong character produces names
Entra rejects individually rather than a single clear failure.

These are also what the seeded Conditional Access policy uses. Without them it falls back to the
tenant's built-in phishing-resistant strength, which works but means the policy references an object
this module did not create and cannot vary.

## EXAMPLES

### Example 1: Creates all three custom strengths

```powershell
New-EntraAuthenticationStrength
```

Output: None

Use case: Called by New-EntraEnvironment, before the policies that reference them

### Example 2: Creates only the phishing-resistant strength

```powershell
New-EntraAuthenticationStrength -StrengthKey strength-phishres -PassThru
```

Output: The strength object, with its allowed combinations.

Use case: Reproducing the policy that no seeded user can satisfy.

### Example 3: Previews all three without creating them

```powershell
New-EntraAuthenticationStrength -WhatIf
```

Output: One WhatIf line per strength.

Use case: Checking the names before a policy is written to reference them.

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

Returns the created strengths

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

### -ShowProgress

Draws a progress bar

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

### -StrengthKey

Creates only the named strengths, by their Key column. Defaults to all of them.

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

### EntraAuthenticationStrength

One object per authentication strength created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraConditionalAccessPolicy]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
