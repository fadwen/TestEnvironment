---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: New-AuthentikFlow
---

# New-AuthentikFlow

## SYNOPSIS

Creates the seeded stages and flows from Data\AuthentikStages.csv and Data\AuthentikFlows.csv, and attaches the flows to seeded providers

## SYNTAX

### __AllParameterSets

```
New-AuthentikFlow [[-FlowName] <string[]>] [-SkipProvider] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates six stages and three flows built from them: a per-application sign-in flow of
identification, password, an optional second factor and log-in, attached to the SAML and proxy
providers; an authorization flow with an explicit, expiring consent step, attached to the expenses
OAuth2 provider in place of the implicit default; and an enrolment flow made of one deny stage,
which the reusable invitation is tied to. Flows are Authentik's signature feature and the seed has
them in the shapes a review has to handle: a second factor that is skipped when the user has none, a
consent that expires, and an enrolment link that admits nobody.

Two things are true by construction and have no parameter to change them. The seed never creates,
edits or binds anything to a flow whose slug does not carry the seed prefix, so the instance's
default flows are never touched; and it never writes to the brand, so no seeded flow ever becomes
the default for anyone. A seeded flow is reached only through a seeded provider or by its own URL. A
test pins both.

Stages are created before the flows that bind them, by type at each type's own endpoint, with their
settings in a Settings cell parsed the same way as the typed policies. A flow's stages are bound in
the order the Stages column lists them, and a re-run finds an existing binding for a stage rather
than stacking another. The flow is then attached to each provider behind the applications its
Applications column names, as the authentication, authorization or invalidation flow its designation
dictates.

## EXAMPLES

### Example 1: Creates every seeded stage and flow and attaches the flows to their providers

```powershell
New-AuthentikFlow
```

Output: None

Use case: Called by New-AuthentikEnvironment after the outposts step

### Example 2: Creates the sign-in flow and the four stages it binds

```powershell
New-AuthentikFlow -FlowName Partner-Authentication -PassThru
```

Output: The flow object with its stages in order and the providers it was attached to

Use case: Testing a sign-in that has to survive a user with no second factor

### Example 3: Lists the stages and flows that would be created, attached to nothing

```powershell
New-AuthentikFlow -SkipProvider -WhatIf
```

Output: One WhatIf line per stage and per flow

Use case: Reviewing the flow shapes before they govern any sign-in

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

### -FlowName

Creates only the named flows, by their Name column, and only the stages they use. Defaults to all of
them.

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

Creates the stages and flows without attaching any flow to a provider.

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

Only when -PassThru is supplied: TotalFlows, CreatedFlows, UpdatedFlows, StagesCreated, StagesUpdated, BindingsCreated, ProvidersUpdated, one entry per flow under Flows with its primary key, CSV key, name, slug, designation, the stages it binds in order and the applications whose providers it was attached to, and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-AuthentikApplication]()
- [New-AuthentikInvitation]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
