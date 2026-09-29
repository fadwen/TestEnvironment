---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 28 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginUser
---

# New-OneLoginUser

## SYNOPSIS

Creates the seeded people with their lifecycle, group, manager and roles, and puts a reused one back as the data describes

## SYNTAX

### __AllParameterSets

```
New-OneLoginUser [[-Username] <string[]>] [[-Tier] <string[]>] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

Creates every seeded person with their lifecycle status and state, their group, their manager and their custom fields in one request, in the order the seed data lists them, which puts every manager before the people who report to them. Then adds each person to their roles, one request per role.

The people are built around what OneLogin does without saying so, each verified against a live trial account:

- A person is approved only while the account has a user licence for them. Beyond that OneLogin makes them Unlicensed, and answers the create as if it had not. A trial has twelve licences, the owner among them, so ten Core people are approved. The writing-system cohort is unlicensed, because what those people test is their names; and every Bulk person is unlicensed on purpose, so a seed spends no licence on a trial or a paid account. This step reads the people back once and reports anybody OneLogin left unlicensed.
- A role grant is accepted for anyone and kept only for an approved person whose status is Active, Suspended, Locked, PasswordExpired or AwaitingPasswordReset. The data gives roles to those people only.
- A rejected person is kept out of any group as well as any role.
- Unactivated and Unapproved do not stay put, so the data does not ask for them.
- A status of Locked sent on a create or an update does not hold either. A person the data gives as Locked is created Active and then locked for a year through OneLogin's lock call, which holds on a licensed person only; a re-run locks them again when less than a month of the lock is left.

Every person also carries the directory identifiers a synchronised account would: a sAMAccountName, a user principal name, a distinguished name, the distinguished names of their groups and roles as member_of, an external id, a phone number and a comment saying what made them. Each is built from the prefix and the connection's email domain - the sAMAccountName and external id start with the prefix, the names sit under OU=<prefix>Users and OU=<prefix>Groups of a domain made from the lab email domain, and every phone number is in the 555-0100 to 555-0199 range reserved for fiction - so no identifier can match an account a real directory synchronises, and a tool that joins on one of them finds the seed and nothing else.

Nobody who is not seeded is ever touched. The people this step adds to roles and names as managers are the ones it created and the ones it proved seeded - by the tag in zztest_seed_tag and the prefix on the username - and the roles and groups it uses are empty or hold seeded people alone. A create refused because the username already belongs to somebody else is reported and left.

Re-running is safe. A person already seeded is reused and put back as the data describes: names, title, department, company, status, state, group, manager, custom fields and directory identifiers, sending only what differs. Names are compared by codepoint, so a decomposed name that came back precomposed is corrected.

OneLogin settles role membership after it is written. A role can read as empty for a short while after its grants were sent.

## EXAMPLES

### Example 1: Create every seeded person

```powershell
New-OneLoginUser -ShowProgress
```

DESCRIPTION: Creates the 321 seeded people, sets their managers and adds the licensed ones to their roles
OUTPUT: A progress bar, and nothing on the pipeline
USE CASE: Run for you by New-TestEnvironment, as the last step

### Example 2: Create the designed people only

```powershell
New-OneLoginUser -Tier Core -PassThru
```

DESCRIPTION: Creates the twenty-one hand-designed people
OUTPUT: A result object with the counts, and an error naming anybody OneLogin left unlicensed
USE CASE: The fast loop, when the test is behaviour rather than scale

### Example 3: Put two people back

```powershell
New-OneLoginUser -Username mbell, jmarchetti -PassThru
```

DESCRIPTION: Recreates or restores the suspended manager and the person who reports to him
OUTPUT: A result object; UpdatedUsers counts the people who were changed back
USE CASE: Repairing a seed after somebody edited those people in the portal

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

Return a result object with TotalUsers, CreatedUsers, ReusedUsers, UpdatedUsers, ManagersSet, UsersLocked, MembershipsApplied, GrantsNotYetShown, Users and Errors.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

Show a progress bar, one step per person.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

Seed only the Core people (the hand-designed edge cases) or only the Bulk people (the generated volume). Both by default.

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

### -Username

Seed only the people with these keys from the seed data - the username without the prefix, such as jnino. All of them by default.

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

Only when -PassThru is supplied: a summary with TotalUsers, CreatedUsers, ReusedUsers, UpdatedUsers, ManagersSet, UsersLocked, MembershipsApplied, GrantsNotYetShown, Users and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginCustomAttribute]()
- [New-OneLoginRole]()
- [New-OneLoginGroup]()

