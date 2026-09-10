---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraGuestUser.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraGuestUser
---

# New-EntraGuestUser

## SYNOPSIS

Creates the external identities defined in Data\EntraGuestUsers.csv

## SYNTAX

### __AllParameterSets

```
New-EntraGuestUser [[-GuestKey] <string[]>] [-SkipGroups] [-ShowProgress] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

Every other user this module seeds is an ordinary cloud member. These four are not, and they exist
because "is this person external?" has no single answer a script can read off one property - which
is precisely what most scripts assume.

Four rows, arranged so that no single test separates the insiders from the outsiders:

- **gpending** is invited and never redeems.
Its externalUserState stays
  PendingAcceptance, which means the account exists, is enabled, and cannot sign in.
  Anything that counts active accounts by accountEnabled counts this one.
- **gmember** is a guest inside dept-engineering, one level down the nesting chain, so
  all-staff reaches an external identity transitively without holding one directly.
Its
  department also satisfies the dyn-engineering rule, so Entra puts it in a dynamic
  group whose author never considered guests.
- **gconverted** is invited as a B2B **member**, which is what a long-running contractor
  becomes.
Its userType is Member, and its UPN still carries #EXT# and its mail is still
  external.
A headcount keyed on userType counts it as staff.
- **glocal** is created directly with userType Guest, so it has an ordinary in-tenant
  UPN, no #EXT# and no externalUserState at all - the exact inverse of gconverted.

Read those last two together: userType alone gets one of them wrong, the #EXT# marker in the UPN
gets the other one wrong, and externalUserState is null for both a local guest and a redeemed one.
That is the point of the pair.

**No invitation email is ever sent.** sendInvitationMessage is false and is not a parameter, so
there is no way to make this module mail anybody. The addresses are on example.com, which RFC 2606
reserves and nobody can register, for the same reason the named locations use RFC 5737 documentation
ranges: a lab object that names a real address is one typo away from reaching a real person. A
contract test asserts both.

The prefix goes in the local part of the invited address rather than the domain, and that is
load-bearing. Entra derives a B2B UPN by replacing the @ in the address, so
ENTRALAB-gmember@example.com becomes ENTRALAB-gmember_example.com#EXT#@tenant. onmicrosoft.com -
which still starts with the prefix, and is therefore still found by the same teardown query as every
other seeded user.

## EXAMPLES

### Example 1: Creates the four external identities and places them in their groups

```powershell
New-EntraGuestUser
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Creates only the guest that never redeems its invitation

```powershell
New-EntraGuestUser -GuestKey gpending -PassThru
```

Output: The created guest, with its mangled UPN and externalUserState

Use case: Reproducing the enabled-but-cannot-sign-in case on its own

### Example 3: Creates the guests without placing them in groups

```powershell
New-EntraGuestUser -SkipGroups -ShowProgress
```

Output: A progress bar, then nothing.

Use case: Testing a report that lists guests with no group membership at all.

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

### -GuestKey

Creates only the named guests, by their Key column. Defaults to all of them.

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

Returns the created guests

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

Draws a progress bar

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

Creates the identities but does not add them to any group

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

### EntraGuestUser

One object per guest created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraUser]()
- [New-EntraGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
