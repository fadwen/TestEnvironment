---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAService
---

# New-FreeIPAService

## SYNOPSIS

Creates the seeded Kerberos services and delegation rules from Data\FreeIPAServices.csv and Data\FreeIPAServiceDelegation.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPAService [[-Principal] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A FreeIPA service is a Kerberos principal on a host, and the seed creates four on seeded hosts: the
HTTP service a delegation rule lets act on a user's behalf, a database service of a custom type that
another host is allowed to manage, an LDAP service on the legacy host that is the delegation target,
and an HTTP service that only issues tickets carrying a second-factor indicator. Then constrained
delegation: a target holding the LDAP service, a rule that lets the web service obtain tickets for
it, and a target with no members.

Every service is added with force, because its host is a seeded record with no DNS entry, and none
is ever given a keytab. A service belongs to its host, so it is found by the prefix on the host part
of its principal and the host being seeded, and it is deleted with the host. Delegation rules and
targets carry no description; the prefix on the name is what they have, and the realm's own
ipa-http-delegation rule and its targets are never named.

## EXAMPLES

### Example 1: Creates every seeded service, delegation target and rule

```powershell
New-FreeIPAService
```

Output: None

Use case: Called by New-FreeIPAEnvironment once the hosts exist

### Example 2: Rebuilds the service with the authentication indicator

```powershell
New-FreeIPAService -Principal HTTP/bastion01 -PassThru
```

Output: The result object with one service

Use case: Testing a report that reads authentication indicators

### Example 3: Lists what would be created without creating it

```powershell
New-FreeIPAService -WhatIf
```

Output: One WhatIf line per service, target and rule

Use case: Confirming the principals before seeding a shared realm

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

### -Principal

Creates only the named services, by their Principal column, and every delegation rule and target.
Defaults to all of them.

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

Only when -PassThru is supplied: TotalServices, CreatedServices, UpdatedServices, DelegationRulesCreated, DelegationTargetsCreated, MembershipsApplied, one entry per service under Services with its CSV key and principal, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAHost]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
