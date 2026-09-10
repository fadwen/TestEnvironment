---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestEdgeCase.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestEdgeCase
---

# New-ADTestEdgeCase

## SYNOPSIS

Creates the awkward directory states that CSV-driven test data cannot express

## SYNTAX

### __AllParameterSets

```
New-ADTestEdgeCase [[-EdgeCase] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

The rest of this module builds a convincing organisation - users, departments, devices, group names.
What it cannot build from a CSV row is the messy directory *state* that maintenance and audit
scripts actually operate on: delegated permissions, access control entries left behind by deleted
principals, legacy Kerberos encryption settings, accounts whose passwords genuinely expire, and two
groups that share a name.

That gap matters more than it sounds. A script that silently reports nothing and a script that
correctly reports nothing produce identical output against a clean directory, so an environment
without these states cannot tell a working audit script from a broken one.

Everything created here lives under OU=EdgeCases inside the test OU structure, and the OUs are
created unprotected. Teardown is therefore a single recursive delete - which matters, because two of
these states (a delegated ACE and a planted orphaned SID) are written into security descriptors
rather than being objects in their own right, and would otherwise outlive the objects they were
attached to.

This function is opt-in and is not called by New-ADEnvironment unless -IncludeEdgeCase is passed.
Planting an unresolvable SID in an ACL is not something that should ever happen implicitly.

## EXAMPLES

### Example 1: Shows everything that would be created without touching the directory

```powershell
New-ADTestEdgeCase -WhatIf
```

Worth doing first - this function writes access control entries.

### Example 2: Creates every edge case under OU=EdgeCases

```powershell
New-ADTestEdgeCase
```

### Example 3: Creates only the two security-descriptor states and returns what it did

```powershell
New-ADTestEdgeCase -EdgeCase AclDelegation, OrphanedSid -PassThru
```

Useful when testing a permissions report or an orphaned-SID cleanup on its own.

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

### -EdgeCase

Which states to create. Defaults to All.

AclDelegation      A group granted GenericAll over an OU, inherited by the objects
                   inside it.
Without this, a permissions report has nothing to find
                   and an empty report looks correct.
OrphanedSid        Access control entries referencing a SID that resolves to nothing,
                   which is what a deleted principal leaves behind.
LegacyEncryption   Accounts carrying DES and RC4-era msDS-SupportedEncryptionTypes
                   values, plus one with USE_DES_KEY_ONLY set in userAccountControl.
PasswordExpiry     Accounts whose passwords actually expire, plus the must-change and
                   smart-card variants that report no expiry for different reasons.
AmbiguousName      Two groups sharing a display name in different OUs, which is the
                   only way to reach the "matched more than one group" path that
                   several scripts implement and nothing otherwise exercises.
MoveTarget         An empty OU for group-move scripts to move things into.
CommaName          Objects whose common name contains a comma, which AD stores
                   escaped as "CN=Acme\, Inc".
Any code that recovers a name by
                   splitting a distinguished name on "," gets the wrong answer and
                   does not fail while doing it.
MissingUpn         A user with no userPrincipalName, reaching the fallback branch
                   that scripts rewriting UPNs carry but never otherwise execute.
MixedMembership    A group holding a computer and a contact.
Membership code that
                   assumes every member is a user or a group silently drops these.
FineGrainedPolicy  A password settings object with a short maximum age, applied to a
                   group, so a password expiry report has something whose expiry
                   comes from an FGPP rather than the domain default.
GovernanceAttribute
                   Groups carrying base-schema attributes a governance export can be
                   pointed at.
See the note about extensionAttribute below.

```yaml
Type: System.String[]
DefaultValue: All
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

Returns a summary object describing what was created.

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

Only when -PassThru is supplied: one entry per edge case, recording what it created and where.

## NOTES

Author: Jeffrey Stuhr

Requires rights to modify security descriptors in the test OU, which is more than
the rest of this module needs.
Run it as an account that can write ACLs.

Remove-ADEnvironment removes OU=EdgeCases and everything beneath it, and the
password settings object created by FineGrainedPolicy, which lives outside that OU
in the domain's Password Settings Container.

GOVERNANCE ATTRIBUTES AND extensionAttribute1-15

A governance export keyed on extensionAttribute1-15 cannot be exercised in a forest
that has never had Exchange prepared, because those attributes reach the group class
through the Exchange schema extension and are simply absent here.

The honest options are to prepare the Exchange schema, or to extend the schema with
custom attributes.
Both are effectively irreversible - an attribute can be
deactivated but never removed from a forest - so neither is done here.

What GovernanceAttribute does instead is populate attributes the base schema already
has and that genuinely mean something close to the columns wanted, so an export can
be pointed at them and its populated path actually runs:

    Comments      -> info               the notes field
    Reviewer      -> adminDescription   administrative annotation
    Documentation -> wWWHomePage        a URL field, holding a runbook link

Three columns exercise the same per-column loop nine would.
Mapping the remaining
six onto unrelated attributes - a yes/no answer written into a URL field, say -
would populate a report with data that means nothing, which is worse than an empty
column because it looks correct.

All three are single-valued.
That is deliberate: an export that assigns an attribute
straight into a CSV cell writes a MULTI-valued one out as the literal string
"Microsoft.ActiveDirectory.Management.ADPropertyValueCollection".
extensionName is
multi-valued and is populated on these groups precisely so that behaviour can be
reproduced on demand by mapping a column to it.

## RELATED LINKS

- [New-ADTestOUStructure]()
- [New-ADTestUser]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
