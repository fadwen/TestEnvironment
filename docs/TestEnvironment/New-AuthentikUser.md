---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikUser
---

# New-AuthentikUser

## SYNOPSIS

Creates the seeded Authentik users from Data\AuthentikUsers.csv, in their groups

## SYNTAX

### __AllParameterSets

```
New-AuthentikUser [[-UserName] <string[]>] [[-AccountPassword] <securestring>] [-SkipGroups]
 [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates ten users: internal staff along a manager chain, two external contractors, a disabled
account that keeps its memberships, an intern with a missing badge id, three names with accents, and
a service account sitting among the humans. Each is the shape that breaks a particular report, and
the Purpose column of the CSV says which.

Authentik has no manager field and no fixed profile schema; it has free-form attributes. Title,
department, manager and the lab attributes all go there, under names beginning lab, and so does the
seed tag. Every user is created under the seed path, a container of the module's own that a listing
can filter on, and human user accounts carry no prefix on their username - the path and the tag are
their evidence of ownership.

Group membership is set on the user, by resolving the CSV group keys to the groups
New-AuthentikGroup created. A group that does not exist is reported and skipped rather than failing
the user.

## EXAMPLES

### Example 1: Creates every seeded user and places them in their groups

```powershell
New-AuthentikUser
```

Output: None

Use case: Called by New-AuthentikEnvironment after the groups step

### Example 2: Creates only the two contractors

```powershell
New-AuthentikUser -UserName hkobayashi, ofitzgerald -PassThru
```

Output: The two user objects, both external type with the contractor flag set

Use case: Testing a policy that must deny contractors without seeding everyone

### Example 3: Creates the users with a password and no memberships

```powershell
$password = Read-Host 'Lab password' -AsSecureString
New-AuthentikUser -AccountPassword $password -SkipGroups
```

Output: None

Use case: Sign-in testing against users that hold no group-derived access

## PARAMETERS

### -AccountPassword

A password to set on every created user. Without it the users exist but cannot sign in, which is
enough for directory-shaped testing and is the safe default on an instance real people use.

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

### -SkipGroups

Creates the users with no group membership.

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

Only when -PassThru is supplied: TotalUsers, CreatedUsers, UpdatedUsers, PasswordsSet, one entry per user under Users with its primary key, username, email, type and memberships, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikGroup]()
- [New-AuthentikPolicy]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
