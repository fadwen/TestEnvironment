---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaApp.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaApp
---

# New-OktaApp

## SYNOPSIS

Creates the seeded app integrations and assigns groups and users to them

## SYNTAX

### __AllParameterSets

```
New-OktaApp [[-AppName] <string[]>] [-SkipAssignment] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Users and groups answer "who". Apps are what turn that into "who has access to what", which is the
question Okta actually exists to answer and the one most scripts written against it are trying to
report on. Without app integrations a seeded tenant cannot exercise assignment, entitlement
reporting, access reviews, or the offboarding question "what can this leaver still reach".

Eight apps, and like the groups they are free: the Integrator Free Plan caps active users at ten but
does not cap apps, so this is where an eight-user tenant gets to look like a real one.

The assignments are the point, not the apps. They cover the shapes that break reports:

- An app assigned to everyone, so a report returning nobody is obviously wrong.
- An app reached through two overlapping groups, which a naive union double-counts.
- A direct assignee who is NOT in the assigned group.
Group-only reports miss them
  entirely, and that is the most common access-review bug there is.
- A user assigned both directly and through a group, so the two scopes have to be
  told apart rather than merged.
- An app assigned to nobody at all.

Three sign-on modes are used: BOOKMARK, BROWSER_PLUGIN (SWA, password-vaulted) and OPENID_CONNECT (a
real client with a secret). Custom SAML apps are deliberately absent because Okta does not permit
creating them through the API - every documented template name returns 404 - so they have to be made
in the admin console. That was verified against a live tenant rather than assumed.

## EXAMPLES

### Example 1: Creates every app and applies its assignments

```powershell
New-OktaApp
```

### Example 2: Creates the app shells only, for testing an assignment script against

```powershell
New-OktaApp -SkipAssignment -PassThru
```

### Example 3: Previews two apps without creating them

```powershell
New-OktaApp -AppName Wiki, Payroll -WhatIf
```

## PARAMETERS

### -AppName

Restrict the operation to these CSV app names, for example Wiki. The prefix is added automatically,
so pass the bare name.

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

### -SkipAssignment

Create the apps but assign nobody to them

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

Only when -PassThru is supplied: a summary with TotalApps, CreatedApps, ExistingApps, GroupsAssigned, UsersAssigned, Apps and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

Groups and users are matched by name and login, so run New-OktaGroup and
New-OktaUser first.
An assignment that does not resolve is reported and skipped
rather than failing the app.

## RELATED LINKS

- [New-OktaGroup]()
- [New-OktaUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
