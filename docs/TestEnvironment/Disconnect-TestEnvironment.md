---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Disconnect-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Disconnect-TestEnvironment
---

# Disconnect-TestEnvironment

## SYNOPSIS

Clears the stored connection for the active provider

## SYNTAX

### __AllParameterSets

```
Disconnect-TestEnvironment [-WhatIf] [-Confirm]
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
Disconnect-TestEnvironment
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Clears the connection and shows what was dropped

```powershell
Disconnect-TestEnvironment -PassThru
```

Output: The provider's disconnect result, naming the tenant, domain or org that was connected.

Use case: Confirming a session is clean before handing the console to someone else.

### Example 3: Switches the session from one provider to another

```powershell
Disconnect-TestEnvironment
Connect-TestEnvironment -Provider Okta -OrgUrl https://dev-123456.okta.com -ServiceApp
```

Output: Nothing from either command; the second fixes Okta as the active provider.

Use case: Seeding a second directory in the same session. Only one provider is active at a time, so
the first connection has to be released.

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

### TestEnvironmentDisconnectResult

Whatever the active provider's disconnect command returns, which is a result object only when -PassThru is mirrored through and supplied.

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
- [Get-TestEnvironmentProvider]()
- [about_TestEnvironment]()
