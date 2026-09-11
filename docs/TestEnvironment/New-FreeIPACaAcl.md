---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPACaAcl
---

# New-FreeIPACaAcl

## SYNOPSIS

Creates the seeded certificate authority access control rules from Data\FreeIPACaAcls.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPACaAcl [[-AclName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A CA ACL says which users, hosts and services may be issued a certificate, from which certificate
authority and through which profile. The realm ships one that lets every host and service use the
service profile; a user certificate needs a rule that names the user or a group, and the seed
creates that rule ahead of the certificates it issues. The rest are shapes for a report: a disabled
pilot that a listing which does not read the flag would count as granting, a scoped rule beside the
stock one that already allows everything it allows, and a rule with every profile and every CA that
is granted to nobody.

Members that are seeded objects are resolved to their realm names; a profile or CA is a stock object
the seed only ever references, named through a builtin: marker. A category set to all is sent as the
category; otherwise the members are added. A rule whose row says Enabled FALSE is disabled after
creation. Every rule carries the seed prefix on its name and the seed marker at the end of its
description, and the stock rule is never named.

## EXAMPLES

### Example 1: Creates every seeded rule

```powershell
New-FreeIPACaAcl
```

Output: None

Use case: Called by New-FreeIPAEnvironment before the certificates are issued

### Example 2: Rebuilds the one rule the user certificates depend on

```powershell
New-FreeIPACaAcl -AclName user-certs -PassThru
```

Output: The result object with one rule

Use case: Restoring the rule after a test deleted it

### Example 3: Lists the rules that would be created without creating them

```powershell
New-FreeIPACaAcl -WhatIf
```

Output: One WhatIf line per rule

Use case: Confirming the members before seeding a shared realm

## PARAMETERS

### -AclName

Creates only the named rules, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalAcls, CreatedAcls, UpdatedAcls, MembershipsApplied, one entry per rule under Acls with its CSV key, name and whether it is enabled, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPACertificate]()
- [New-FreeIPAGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
