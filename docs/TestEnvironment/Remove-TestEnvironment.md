---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Remove-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Remove-TestEnvironment
---

# Remove-TestEnvironment

## SYNOPSIS

Removes everything the active provider created, and nothing else

## SYNTAX

### __AllParameterSets

```
Remove-TestEnvironment [-WhatIf] [-Confirm]
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
Remove-TestEnvironment
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Shows what teardown would remove, and what it would refuse

```powershell
Remove-TestEnvironment -WhatIf
```

Output: One WhatIf line per object the module can prove it owns.

Use case: Always the first teardown call. -WhatIf wins over -Force on every destructive command in
this module.

### Example 3: Removes the seeded users and groups but keeps the policies

```powershell
Remove-TestEnvironment -Keep ConditionalAccessPolicies, NamedLocations -Force -PassThru
```

Output: A summary of what was removed per object type.

Use case: Re-seeding people without disturbing the policy objects a report has already been written
against. -Keep is mirrored from the Entra and Okta providers.

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

### TestEnvironmentTeardownResult

When -PassThru is supplied: what was removed per object type, and what was left alone because the module could not prove it owned it.

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

- [New-TestEnvironment]()
- [Get-TestEnvironmentReport]()
- [Update-TestContainment]()
- [about_TestEnvironment]()
