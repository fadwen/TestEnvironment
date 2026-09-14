---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Repair-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 14 2026
PlatyPS schema version: 2024-05-01
title: Repair-TestEnvironment
---

# Repair-TestEnvironment

## SYNOPSIS

Puts back what verification found missing, by re-running only the seed steps that own it

## SYNTAX

### __AllParameterSets

```
Repair-TestEnvironment [-SkipMembership] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Runs Test-TestEnvironment against the active provider, works out from what failed which seed steps
own the missing objects, re-runs those steps alone through the provider's own orchestrator, and
verifies again. Every seed step is idempotent, so what exists is reused and what is missing is
created; a name that came back wrong is repaired the same way where the provider's user step
updates an existing user.

Each provider says in its Initialize.ps1 which step owns which check, and which steps run alongside
any repair: the administrative units and the containment pass on Entra, the OU structure on Active
Directory, because a repaired object has to have a container and land in it. A test holds every
provider's map to covering every check its verifier judges, so a check cannot be added without saying
which step puts it back.

What is there that the data does not describe is reported and left alone. Removing an object the
module owns is teardown's job, with its confirmation, not repair's.

The provider's own switches are not mirrored here: repair runs the steps with their defaults.

## EXAMPLES

### Example 1: Repairs whatever a partial seed left out

```powershell
Repair-TestEnvironment
```

Output: The checks that failed, the steps re-run for them, and the second verification's verdict.

Use case: A seed that lost a step to a throttled hour, or an object somebody deleted by hand.

### Example 2: Shows what a repair would run

```powershell
Repair-TestEnvironment -WhatIf
```

Output: The failed checks and the steps that own them; nothing runs.

Use case: Deciding whether to repair or to tear down and re-seed.

### Example 3: Repairs without the membership reads

```powershell
$repair = Repair-TestEnvironment -SkipMembership
$repair.After.Checks | Where-Object { $_.Passed -eq $false }
```

Output: The repair result, and whatever still fails after it.

Use case: Membership reads are the expensive part of verification on a large seed; this skips them
on both sides and lists what a second look should be about.

## PARAMETERS

### -SkipMembership

Verify without reading memberships, before and after, which is the expensive part.

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

### TestEnvironmentRepair

Provider, Before (the first verification), StepsRun, SeedResult (the orchestrator's result), After
(the second verification, or $null under -WhatIf) and Repaired, which is $true when the second
verification passed.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Test-TestEnvironment]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
