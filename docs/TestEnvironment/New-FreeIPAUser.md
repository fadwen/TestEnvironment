---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAUser
---

# New-FreeIPAUser

## SYNOPSIS

Creates the seeded FreeIPA users from Data\FreeIPAUsers.csv, in their groups and lifecycle states

## SYNTAX

### __AllParameterSets

```
New-FreeIPAUser [[-UserName] <string[]>] [[-Tier] <string[]>] [[-AccountPassword] <securestring>]
 [-SkipGroups] [-ShowProgress] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates around three hundred users in two tiers. The Core tier is twelve hand-designed rows chosen
to be awkward: accented names, a disabled account that keeps every membership, a hire who has not
started and is staged, a leaver who was preserved, a contractor whose Kerberos principal expired
while the account stayed enabled, a user whose authentication type demands a token, a user with no
private group, a service account with no shell, a user with two public keys and one with certificate
mapping data. The Bulk tier is the AD provider's people and service accounts mapped across with
their titles, org units, employee numbers, addresses and manager chains.

FreeIPA has four states a user can be in and the seed creates each as its row says. Active is a
plain add; Disabled is an add followed by user-disable, which keeps every membership; Staged is an
add into the staging container, where the entry is invisible to user-find and cannot hold a
membership until it is activated; Preserved is an add, the memberships, and then a preserving
delete, which strips every membership and keeps the entry for the audit trail. Managers are created
before the people who report to them, so the chain is real all the way up.

Passwords are set only when -AccountPassword is supplied. A row whose PasswordState is MustChange
gets the password as an administrator sets it, which FreeIPA marks expired on the spot; a row that
says Current gets a temporary one and then changes it as the user, which is the only way to a
password that is not. The strictest seeded password policy applies to some of those users once
New-FreeIPAPasswordPolicy has run, so the password should satisfy twenty characters of four classes.

Every user carries the seed tag in its userclass beside its class, and membership is applied after
every user exists, one call per group. A re-run updates the attributes of a user that exists and
leaves a preserved one preserved.

## EXAMPLES

### Example 1: Creates every seeded user in every lifecycle state, in their groups

```powershell
New-FreeIPAUser
```

Output: None

Use case: Called by New-FreeIPAEnvironment after the groups step

### Example 2: Creates the twelve designed users with passwords

```powershell
New-FreeIPAUser -Tier Core -AccountPassword $password -PassThru
```

Output: The result object with twelve users and the passwords set

Use case: A fast rebuild for testing sign-in behaviour

### Example 3: Shows what the disabled and the preserved user would be created as

```powershell
New-FreeIPAUser -UserName talvarez, rokafor -WhatIf
```

Output: One WhatIf line per user and per state change

Use case: Confirming the lifecycle handling before seeding a shared realm

## PARAMETERS

### -AccountPassword

A password to set on the seeded users whose row asks for one. Without it no password is set and
nobody can log in.

```yaml
Type: System.Security.SecureString
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
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

Returns the result object.

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

Draws a progress bar, one step per row. Worth having at three hundred users.

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

### -SkipGroups

Creates the users without placing them in groups.

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

### -Tier

Creates only Core rows (the twelve designed edge cases) or only Bulk rows (the volume mapped from
the AD provider). Defaults to both.

```yaml
Type: System.String[]
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

### -UserName

Creates only the named users, by their Username column. Defaults to all of them.

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

### System.Management.Automation.PSObject

Only when -PassThru is supplied: TotalUsers, CreatedUsers, UpdatedUsers, StagedUsers, PreservedUsers, DisabledUsers, PasswordsSet, MembershipsApplied, one entry per user under Users with its login, name, lifecycle, class and memberships, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAGroup]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
