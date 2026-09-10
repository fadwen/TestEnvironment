---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraNamedLocation.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraNamedLocation
---

# New-EntraNamedLocation

## SYNOPSIS

Creates the named locations Conditional Access policies condition on

## SYNTAX

### __AllParameterSets

```
New-EntraNamedLocation [[-LocationKey] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three named locations: a trusted IP range, an untrusted one, and a country location covering
every usageLocation the seeded users carry.

Every IP range is an IANA documentation block - 192.0.2.0/24, 198.51.100.0/24 and 203.0.113.0/24,
reserved by RFC 5737 precisely so they can appear in examples without belonging to anybody. That
matters more than tidiness here. These locations are created in a tenant that is in real use, and a
policy conditioned on a range somebody actually routes through is a policy that can lock a real
person out of a real account.

The trusted flag on the corporate range is not cosmetic. Several controls treat a trusted location
as materially different from a merely known one - it is what suppresses risk-based prompting - so a
lab that marks nothing trusted cannot reproduce the behaviour that flag causes.

Country locations name ISO 3166-1 alpha-2 codes, and the seeded set is chosen to cover the
usageLocation of every seeded user. A country condition that matches none of your test users tells
you nothing when it fails to fire.

## EXAMPLES

### Example 1: Creates all three named locations

```powershell
New-EntraNamedLocation
```

Output: None

Use case: Called by New-EntraEnvironment before the policies that reference them

### Example 2: Creates the two IP locations a geo policy contrasts

```powershell
New-EntraNamedLocation -LocationKey loc-corporate, loc-suspect -PassThru
```

Output: The two named location objects.

Use case: Exercising a Conditional Access evaluation that depends on trusted versus untrusted
ranges.

### Example 3: Previews every location

```powershell
New-EntraNamedLocation -WhatIf
```

Output: One WhatIf line per location.

Use case: Checking the ranges do not collide with anything real in the tenant.

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

### -LocationKey

Creates only the named locations, by their Key column. Defaults to all of them.

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

Returns the created locations

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

### EntraNamedLocation

One object per named location created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraConditionalAccessPolicy]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
