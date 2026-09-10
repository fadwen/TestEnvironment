---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikOutpost
---

# New-AuthentikOutpost

## SYNOPSIS

Creates the seeded outposts from Data\AuthentikOutposts.csv, carrying the seeded providers

## SYNTAX

### __AllParameterSets

```
New-AuthentikOutpost [[-OutpostName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates three outposts, one of each type an outpost can be: a proxy outpost carrying the intranet's
proxy provider, an LDAP outpost carrying the directory provider, and a RADIUS outpost carrying the
network provider. An outpost is the record of where a provider of those types is served from, and it
is created here with no service connection, so nothing is deployed and nothing listens: the record
exists in the state an inventory has to tell apart from a running one, and the seed never asks the
instance to start a container.

Each outpost's providers are resolved from the seeded applications its Applications column names, by
slug, and a provider of the wrong type for the outpost is reported and left off. An outpost has a
name and a managed flag and nothing else to write to, so the seed prefix on the name is the evidence
of ownership, and only unmanaged outposts are ever claimed, since the embedded outpost is
Authentik's own.

## EXAMPLES

### Example 1: Creates every seeded outpost with its providers

```powershell
New-AuthentikOutpost
```

Output: None

Use case: Called by New-AuthentikEnvironment after the applications step

### Example 2: Creates the proxy outpost only

```powershell
New-AuthentikOutpost -OutpostName 'Edge Proxy' -PassThru
```

Output: The outpost object with the provider it carries

Use case: Testing an inventory that must show an outpost with nothing deployed behind it

### Example 3: Lists the outposts that would be created

```powershell
New-AuthentikOutpost -WhatIf
```

Output: One WhatIf line per outpost

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

### -OutpostName

Creates only the named outposts, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalOutposts, CreatedOutposts, UpdatedOutposts, one entry per outpost under Outposts with its primary key, CSV key, name, type, the applications whose providers it carries and a Deployed flag that is always false, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikApplication]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
