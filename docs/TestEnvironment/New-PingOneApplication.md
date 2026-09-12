---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-PingOneApplication.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 12 2026
PlatyPS schema version: 2024-05-01
title: New-PingOneApplication
---

# New-PingOneApplication

## SYNOPSIS

Creates the seeded applications across every protocol and grants them their resource scopes

## SYNTAX

### __AllParameterSets

```
New-PingOneApplication [[-Key] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

The trial's sample data ships no customer application at all: every application in a
fresh environment is PingOne's own console, portal or self-service page.
Those are
platform applications, recognised here by type rather than name, and this module never
creates, edits or deletes any of them.

What is seeded instead covers each shape an access review has to understand:

- An ordinary confidential web application with a secret, assigned to a group.
- A second one assigned to a one-member group, so widening access by one person shows.
- A single-page application with no secret at all.
A public client that authenticates
  with PKCE instead is the shape a review most often mistakes for a misconfiguration.
- A native application with a custom-scheme redirect and a refresh token, which URL
  validation routinely rejects.
- A SAML application, so anything that assumes every application has an OIDC client id
  has one that does not.
- A disabled application assigned to nobody, which an inventory still has to list and
  a review still has to explain.

Access is restricted to groups through the application's access control, set when the
application is created.
Scopes are granted afterwards, one grant per resource, because
a grant names a resource and the scopes on it that the application may request.

A public client is created with PKCE required.
That is not a test condition, it is the
only safe way to run one, and seeding an unsafe public client would be seeding a live
weakness rather than inert data.

Every application is created with its tag in the description, and its redirect URLs are
written against the connection's email domain, which defaults to a reserved example.com
name so no seeded application can redirect to a host anyone owns.

Re-running is safe: an application that already exists is reused, and a grant already
present is left alone.

## EXAMPLES

### EXAMPLE 1

New-PingOneApplication

DESCRIPTION: Creates every seeded application and grants their scopes
OUTPUT: None
USE CASE: The last object step of New-TestEnvironment

### EXAMPLE 2

New-PingOneApplication -Key portal-spa, field-native -PassThru

DESCRIPTION: Creates just the two public clients
OUTPUT: A result object naming them and their grants
USE CASE: Testing how a review treats applications with no secret

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

### -Key

Create only the named applications.
All of them by default.

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

Return a result object describing what was created.

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

Only when -PassThru is supplied: a summary with TotalApplications, CreatedApplications, ReusedApplications, GrantsApplied, Applications and Errors. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-PingOneResource
New-PingOneGroup]()
