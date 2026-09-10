---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikScopeMapping
---

# New-AuthentikScopeMapping

## SYNOPSIS

Creates the seeded OAuth2 scope mappings from Data\AuthentikScopeMappings.csv and attaches them to providers

## SYNTAX

### __AllParameterSets

```
New-AuthentikScopeMapping [[-MappingName] <string[]>] [-SkipProvider] [-PassThru] [-WhatIf]
 [-Confirm]
```

## DESCRIPTION

Creates three scope mappings, each an expression that turns the lab attributes on a user into
claims: a profile scope carrying department, title, clearance and badge, an entitlements scope
carrying a list, and a risk scope with no consent description, so the user is never told it is in
the token. Each mapping is then attached to the OAuth2 providers behind the seeded applications its
Applications column names, merged with the mappings the provider already carries so the standard
OpenID scopes are kept.

Custom claims are where most real integration bugs live, and Authentik makes every one of them from
an expression over attributes, so this is the shape a token-consuming test has to handle: a nested
object, a list-valued claim, and a claim the consent screen never mentioned.

A scope mapping has a name and a managed flag and nothing else to write to, so the seed prefix on
the name is the evidence of ownership, and only unmanaged mappings are ever claimed, since a managed
one belongs to Authentik itself.

## EXAMPLES

### Example 1: Creates every seeded scope mapping and attaches it to its providers

```powershell
New-AuthentikScopeMapping
```

Output: None

Use case: Called by New-AuthentikEnvironment after the applications step

### Example 2: Creates the risk scope only, attached to payroll

```powershell
New-AuthentikScopeMapping -MappingName Lab-Risk -PassThru
```

Output: The mapping object with the providers it was attached to

Use case: Testing a consumer against a claim the user never consented to seeing

### Example 3: Lists the mappings that would be created, attached to nothing

```powershell
New-AuthentikScopeMapping -SkipProvider -WhatIf
```

Output: One WhatIf line per mapping

Use case: Reviewing the expressions before they shape any token

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

### -MappingName

Creates only the named mappings, by their Name column. Defaults to all of them.

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

### -SkipProvider

Creates the mappings without attaching them to any provider.

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

Only when -PassThru is supplied: TotalMappings, CreatedMappings, UpdatedMappings, ProvidersUpdated, one entry per mapping under Mappings with its primary key, CSV key, name, scope name and the applications it was attached to, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikApplication]()
- [New-AuthentikUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
