---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestGroupPolicy.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestGroupPolicy
---

# New-ADTestGroupPolicy

## SYNOPSIS

Creates the companion Group Policy object that denies logon to the test service accounts.

## SYNTAX

### __AllParameterSets

```
New-ADTestGroupPolicy [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

New-ADTestServiceAccount documents that its accounts should be denied interactive, remote
interactive and network logon, but cannot apply that itself: those are LSA account rights granted
per machine, not attributes New-ADUser can set. This creates the GPO that carries them.

The policy is deliberately narrow:

- It is named and commented so it is obviously test data.
- It is linked ONLY to OU=Devices,OU=TestData.
User rights assignment is Computer
  Configuration, so it must be linked where the machines are; linking it over the
  ServiceAccounts OU would have no effect.
It is never linked at the domain root.
- It names only accounts found in the test ServiceAccounts OU.
- Remove-ADEnvironment deletes it, matching on the marker in its comment as
  well as the name so it cannot remove a real policy that happens to share a name.

User rights cannot be written through the GroupPolicy cmdlets, so the [Privilege Rights] section is
written into the GPO's GptTmpl.inf in SYSVOL, the Security client-side extension is registered on
the GPO object, and the version is bumped so clients pick the change up. The SYSVOL location is read
from the GPO's gPCFileSysPath attribute rather than assembled by hand.

In a test environment built by this module the computer objects are synthetic, so no machine
actually processes the policy. It exists so that tooling which audits GPOs, user rights or service
account hardening finds a realistic object to read.

## EXAMPLES

### Example 1: Creates the deny-logon policy and links it to the test Devices OU

```powershell
New-ADTestGroupPolicy
```

### Example 2: Shows what would be created without making changes

```powershell
New-ADTestGroupPolicy -WhatIf
```

### Example 3: Creates the policy and returns the account count and link target

```powershell
$result = New-ADTestGroupPolicy -PassThru
```

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

Returns a PSCustomObject describing what was created.

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

Only when -PassThru is supplied: the GPO created, the OU it was linked to and the number of accounts it denies.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

Requires the GroupPolicy module (RSAT-GPMC) and rights to create and link a GPO.

## RELATED LINKS

- [New-ADTestDevice]()
- [New-ADTestOUStructure]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
