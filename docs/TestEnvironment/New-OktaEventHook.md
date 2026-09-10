---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaEventHook.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaEventHook
---

# New-OktaEventHook

## SYNOPSIS

Creates the seeded event hooks

## SYNTAX

### __AllParameterSets

```
New-OktaEventHook [[-HookName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

An event hook is an outbound webhook: Okta POSTs to a URL when the events you subscribe to occur. A
fresh org has none, so anything that audits outbound integrations has nothing to find until these
exist.

Two hooks, subscribed to events this lab actually generates. The lifecycle hook fires on create,
suspend and delete - all of which the seeded users go through - and the group hook fires on
membership changes, which the group rules produce on their own without anybody doing anything. So
the hooks are not inert decoration; they correspond to traffic the environment really creates.

The URL is under example.com rather than the lab domain, and that is not a preference. Okta
VALIDATES the hook URL and rejects a hostname that does not resolve:
https://hooks.oktalab.example.com/events fails with "Invalid URL provided", while
https://example.com/... is accepted. Verified against a live tenant. example.com is IANA-reserved
and does resolve, which makes it the only address that is both safe and acceptable to Okta.

Nothing is listening at the other end, so deliveries will fail. That is fine and expected for a lab,
and it is itself worth having: a hook whose deliveries fail is a state monitoring should notice.

## EXAMPLES

### Example 1: Creates every event hook and returns the results

```powershell
New-OktaEventHook -PassThru
```

### Example 2: Previews one hook without creating it

```powershell
New-OktaEventHook -HookName Lifecycle-Watcher -WhatIf
```

Output: One WhatIf line naming the hook and its endpoint.

Use case: Checking the endpoint URL before a hook is created that Okta will try to verify against
it.

### Example 3: Creates every hook with no output

```powershell
New-OktaEventHook
```

Output: None.

Use case: Called by New-TestEnvironment during a full Okta seed.

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

### -HookName

Restrict the operation to these CSV hook names

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

Only when -PassThru is supplied: a summary with TotalHooks, CreatedHooks, ExistingHooks, Hooks and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Okta creates these ACTIVE but unverified.
Verification requires the endpoint to answer
a challenge, which nothing here does, so they are created and left alone.

## RELATED LINKS

- [New-OktaTrustedOrigin]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
