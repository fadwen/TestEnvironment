---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OktaUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-OktaUser
---

# New-OktaUser

## SYNOPSIS

Creates the seeded Okta users from Data\OktaUsers.csv

## SYNTAX

### __AllParameterSets

```
New-OktaUser [[-UserCount] <int>] [[-AccountPassword] <securestring>] [-SkipLifecycleStates]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates eight users, which is not an arbitrary number: the Okta Integrator Free Plan licenses ten
active users and your own admin account is one of them, so eight is what fits with a slot left over
for a colleague or a second admin.

Because there are only eight, each one has to earn its place. They differ from each other along the
axes that actually break scripts:

- Three carry non-ASCII names (José Niño, Zoë Müller, Tomás Álvarez) while their
  logins stay ASCII, which is what a real directory looks like.
Windows PowerShell
  writes CSV as ASCII unless told otherwise and silently replaces those characters
  with question marks, so without them that data loss is invisible.
- Three lifecycle states: active, suspended and staged.
A staged user has never signed
  in and has no established credentials, but it still counts against the tenant's
  active user licence and it is still evaluated by group rules.
Both of those were
  verified against a real tenant, and both are the opposite of what people assume.
- Two contractors with an end date, and six permanent staff without one, so empty
  optional attributes are represented rather than assumed away.
- A manager chain three deep, so a script that resolves managers has something to
  resolve.

The function is re-runnable. An existing login is updated rather than duplicated, which matters when
a seed run fails partway and you want to fix the cause and run it again rather than tear down first.

## EXAMPLES

### Example 1: Creates all eight users in their CSV-defined lifecycle states

```powershell
New-OktaUser
```

### Example 2: Creates four uniformly active users, leaving six licence slots free

```powershell
New-OktaUser -UserCount 4 -SkipLifecycleStates -PassThru
```

### Example 3: Seeds the users with a password you choose

```powershell
$password = Read-Host 'Lab password' -AsSecureString
New-OktaUser -AccountPassword $password
```

## PARAMETERS

### -AccountPassword

Password for the seeded accounts, as a SecureString. Defaults to a known, shared, weak value. That
is deliberate: these are lab accounts and being able to sign in as one is usually the point. Pass
your own to override it.

A password is always set, even on the staged user, because creating an Okta user without credentials
makes Okta send a real activation email to the address on the profile.

```yaml
Type: System.Security.SecureString
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
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

### -SkipLifecycleStates

Create every user active, ignoring the Suspended and Staged states in the CSV. Useful when you want
eight uniformly usable accounts and not the awkward ones.

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

### -UserCount

How many users to create, taken from the top of the CSV. Lower it if the tenant is already holding
users you want to keep.

```yaml
Type: System.Int32
DefaultValue: 8
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

### System.Management.Automation.PSObject

Only when -PassThru is supplied: a summary with TotalUsers, CreatedUsers, UpdatedUsers, Users and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr

The custom attributes these users carry must exist first.
Run
New-OktaProfileAttribute, or let New-OktaEnvironment order it for you.

## RELATED LINKS

- [New-OktaProfileAttribute]()
- [New-OktaGroup]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
