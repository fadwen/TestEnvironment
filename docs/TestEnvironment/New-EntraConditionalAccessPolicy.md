---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraConditionalAccessPolicy.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraConditionalAccessPolicy
---

# New-EntraConditionalAccessPolicy

## SYNOPSIS

Creates the seeded Conditional Access policies, always in report-only state

## SYNTAX

### __AllParameterSets

```
New-EntraConditionalAccessPolicy [[-PolicyKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

Creates eight Conditional Access policies covering the control shapes that outcome evaluation has to
get right: a plain MFA grant, a device-compliance grant that is unsatisfiable for anyone on a
non-compliant device, a legacy-authentication block, an inverted location condition, a
risk-conditioned policy, a session-controls-only policy with no grant control at all, an
authentication strength, and an AND of two controls where satisfying one is not enough.

Every one of them is created in enabledForReportingButNotEnforced, and there is no parameter to
change that. This is the single most consequential decision in the module and it is deliberately not
configurable.

A Conditional Access policy is the one object here that can deny a real person access to a real
account. These are seeded into a tenant that is in real use, alongside policies that genuinely
protect it. A report-only policy is fully evaluated and fully logged - it appears in sign-in logs,
it can be read back, and What If will return it - but it never denies anything. That gives the whole
value of having the policies for none of the risk. Anything that wants one enforced can enable it
deliberately in the portal, having read it, which is a decision a human should make once rather than
a switch a script flips by default.

Scoping is to seeded groups only, never to all users. A policy scoped to all users in a live tenant
is how a lab object stops being a lab object, and report-only or not, it would appear in every
sign-in log entry for every real person in the directory.

Authentication strengths are looked up by display name at run time rather than by the well-known
GUID. The built-in strengths do have fixed ids, but resolving them by name means the policy still
builds against a tenant where somebody has replaced the built-in with a custom strength of the same
name - which is exactly the case a baseline is supposed to catch.

## EXAMPLES

### Example 1: Creates all eight policies, every one report-only

```powershell
New-EntraConditionalAccessPolicy
```

Output: None

Use case: Called by New-EntraEnvironment, and the input CaOutcome evaluates against

### Example 2: Creates just the policy that is unsatisfiable on a non-compliant device

```powershell
New-EntraConditionalAccessPolicy -PolicyKey ca-compliant-device -PassThru
```

Output: The policy object

Use case: Reproducing the promotion that locks out an unmanaged device

### Example 3: Previews every policy, confirming each is report-only

```powershell
New-EntraConditionalAccessPolicy -WhatIf
```

Output: One WhatIf line per policy.

Use case: The check to run before seeding a tenant that real people sign in to. The module cannot
create an enforcing policy, and this is where to see that.

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

Returns the created policies

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

### -PolicyKey

Creates only the named policies, by their Key column. Defaults to all of them.

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

### EntraConditionalAccessPolicy

One object per policy created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraNamedLocation]()
- [New-EntraAuthenticationStrength]()
- [New-EntraGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
