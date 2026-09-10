---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-TestEnvironment
---

# New-TestEnvironment

## SYNOPSIS

Seeds the complete test environment through the active provider

## SYNTAX

### __AllParameterSets

```
New-TestEnvironment [-WhatIf] [-Confirm]
```

## DESCRIPTION

Dispatches to the provider the session is connected through, which was fixed by
Connect-TestEnvironment. The provider is deliberately not a parameter here: naming it again on every
call is how a script ends up seeding one directory and tearing down another, and the connection
already knows the answer.

The provider's own parameters are mirrored onto this function at binding time, so provider-specific
switches keep working through it with tab completion and validation intact, and a parameter the
provider does not have fails at binding rather than being quietly dropped.

## EXAMPLES

### Example 1: Runs against the connected provider

```powershell
New-TestEnvironment
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Seeds everything except the pieces that need licences or enforce policy

```powershell
New-TestEnvironment -Skip Licenses, ConditionalAccessPolicies -ShowProgress
```

Output: A progress bar per phase and a summary at the end.

Use case: A tenant with no spare SKUs. -Skip takes the Entra provider's phase names when Entra is
active, and the AD or Okta names otherwise.

### Example 3: Previews the whole seed without creating anything

```powershell
New-TestEnvironment -WhatIf
```

Output: One WhatIf line per object that would be created.

Use case: The first run against any directory that also holds real work.

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

### TestEnvironmentResult

The provider's seed result when -PassThru is mirrored through and supplied: counts per object type and any errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

SupportsShouldProcess is declared but ShouldProcess is never called here.
Both halves are
deliberate.
Declaring it is what makes -WhatIf and -Confirm bind at all: they are optional
common parameters, so a wrapper that omits it rejects "-WhatIf" as an unknown parameter
rather than forwarding it - which is how a dispatch layer silently takes -WhatIf away from
every command behind it.
Not calling it is what keeps the prompt in one place: the
provider function does the work, knows what it is about to touch, and carries its own
ConfirmImpact.
A wrapper that prompted as well would ask twice for one action.

## RELATED LINKS

- [Connect-TestEnvironment]()
- [Get-TestEnvironmentReport]()
- [Remove-TestEnvironment]()
- [Update-TestContainment]()
- [about_TestEnvironment]()
