---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Update-TestContainment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Update-TestContainment
---

# Update-TestContainment

## SYNOPSIS

Places any seeded object that is not in its container

## SYNTAX

### __AllParameterSets

```
Update-TestContainment [-WhatIf] [-Confirm]
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
Update-TestContainment
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Re-contains only users and groups

```powershell
Update-TestContainment -ObjectType Users, Groups -PassThru
```

Output: Per type, how many seeded objects were already in their administrative unit and how many
were added.

Use case: After creating extra seeded users by hand and wanting teardown to find them.

### Example 3: Reports drift without changing anything

```powershell
Update-TestContainment -WhatIf
```

Output: One WhatIf line per object that would be moved into a unit.

Use case: Checking whether a teardown will be complete before running it.

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

### TestContainmentResult

When -PassThru is supplied: per object type, how many seeded objects were already in their administrative unit and how many were added.

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

- [New-EntraAdministrativeUnit]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
