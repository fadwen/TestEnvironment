---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPAIdentityProvider
---

# New-FreeIPAIdentityProvider

## SYNOPSIS

Creates the seeded RADIUS proxies and external identity providers from Data\FreeIPAIdentityProviders.csv

## SYNTAX

### __AllParameterSets

```
New-FreeIPAIdentityProvider [[-ProviderName] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

A user whose authentication type is radius or idp authenticates somewhere else, and the realm has to
know where: a RADIUS proxy names the server and the shared secret, an external identity provider
names the OAuth endpoints and the client. The seed creates both kinds ahead of the users, so the
users step can link a user to one. The rows make the shapes a review has to notice: a proxy pointed
at the legacy box that one user really authenticates through, a proxy pointed at a server that does
not exist which nobody links to, a provider one contractor signs in through, and a pilot provider
with no user linked.

The secrets - a RADIUS shared secret, an OAuth client secret - are generated here at random, sent
once, and never kept or returned; nothing in the seed needs to use them. A provider is created from
FreeIPA's own template for its kind, so the endpoints are the real ones for GitHub or a Keycloak
realm at the seeded address. Every object carries the seed prefix; a proxy also carries the marker
in its description, and a provider, which has no description, is owned by its prefix alone.

## EXAMPLES

### Example 1: Creates every proxy and provider

```powershell
New-FreeIPAIdentityProvider
```

Output: None

Use case: Called by New-FreeIPAEnvironment before the users, which link to them

### Example 2: Rebuilds the one proxy a user authenticates through

```powershell
New-FreeIPAIdentityProvider -ProviderName legacy-radius -PassThru
```

Output: The result object with one provider

Use case: Restoring the proxy after a test deleted it, before re-running the users step

### Example 3: Lists what would be created

```powershell
New-FreeIPAIdentityProvider -WhatIf
```

Output: One WhatIf line per row

Use case: Confirming the names before seeding a shared realm

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

### -ProviderName

Creates only the named rows, by their Name column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalProviders, CreatedProxies, UpdatedProxies, CreatedIdps, UpdatedIdps, one entry per row under Providers with its CSV key, name and kind, and Errors. No secret is in it. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPAUser]()
- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
