---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikInvitation
---

# New-AuthentikInvitation

## SYNOPSIS

Creates the seeded enrolment invitations from Data\AuthentikInvitations.csv

## SYNTAX

### __AllParameterSets

```
New-AuthentikInvitation [[-InvitationName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three invitations: a live single-use one with the enrolment fields filled in, a reusable one
that admits anyone holding the link, and one with a year to run, still valid long after the hire it
was made for fell through. An invitation is a credential in everything but name, and the three
states are what an onboarding report has to tell apart. None is seeded already expired, because
Authentik hides and purges an expired invitation, and one that cannot be listed cannot be reported
on or torn down. The reusable invitation is tied to the seeded enrolment flow that only refuses,
by the Flow column, so the link everyone holds admits nobody; the others can be used by any
enrolment flow.

The fixed data an invitation carries is written into the enrolment prompt, and the seed tag is added
to it, which together with the slug prefix on the name is the evidence teardown proves ownership by.
No invitation is tied to a flow, so none of them can be redeemed unless an administrator points an
enrolment flow at it.

## EXAMPLES

### Example 1: Creates every seeded invitation

```powershell
New-AuthentikInvitation
```

Output: None

Use case: Called by New-AuthentikEnvironment as its last step

### Example 2: Creates the long-lived invitation only

```powershell
New-AuthentikInvitation -InvitationName forgotten-offer -PassThru
```

Output: The invitation object with its expiry a year out

Use case: Testing a report that has to flag invitations that outlive their purpose

### Example 3: Lists the invitations that would be created

```powershell
New-AuthentikInvitation -WhatIf
```

Output: One WhatIf line per invitation

Use case: Confirming the names before seeding a shared instance

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

### -InvitationName

Creates only the named invitations, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalInvitations, CreatedInvitations, UpdatedInvitations, one entry per invitation under Invitations with its primary key, CSV key, name, expiry, whether it is single use and the seeded flow it is tied to, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
