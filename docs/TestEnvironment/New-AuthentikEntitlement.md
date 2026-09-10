---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikEntitlement
---

# New-AuthentikEntitlement

## SYNOPSIS

Creates the seeded application entitlements from Data\AuthentikEntitlements.csv

## SYNTAX

### __AllParameterSets

```
New-AuthentikEntitlement [[-EntitlementName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates six entitlements across four seeded applications: a submitter and an approver on expenses,
an administrator on payroll, an editor and a reader on the wiki, and an operator on the hidden
utility. An entitlement is Authentik's per-application assignment, the analogue of an Entra app
role, and it grants nothing by itself: a binding attaches it to a group or a user, and
New-AuthentikBinding creates those. The reader entitlement is deliberately never bound, because an
entitlement nobody holds is a finding an access report has to show rather than an error.

Each entitlement is named with the seed prefix and carries the seed tag and its CSV key in its
attributes, which together with belonging to a seeded application is the evidence teardown proves
ownership by. Entitlements are read back per application, because that is the only filter the
endpoint offers.

## EXAMPLES

### Example 1: Creates every seeded entitlement on its application

```powershell
New-AuthentikEntitlement
```

Output: None

Use case: Called by New-AuthentikEnvironment after the applications step

### Example 2: Creates the two expense entitlements only

```powershell
New-AuthentikEntitlement -EntitlementName expenses/Approver, expenses/Submitter -PassThru
```

Output: The two entitlement objects with their binding UUIDs

Use case: Testing an approval workflow that reads entitlements from the token

### Example 3: Lists the entitlements that would be created

```powershell
New-AuthentikEntitlement -WhatIf
```

Output: One WhatIf line per entitlement

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

### -EntitlementName

Creates only the named entitlements, as Application/Name, for example expenses/Approver. Defaults to
all of them.

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

Only when -PassThru is supplied: TotalEntitlements, CreatedEntitlements, UpdatedEntitlements, one entry per entitlement under Entitlements with its policy-binding UUID, CSV key, name and application slug, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikApplication]()
- [New-AuthentikBinding]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
