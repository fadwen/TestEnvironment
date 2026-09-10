---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Connect-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Connect-TestEnvironment
---

# Connect-TestEnvironment

## SYNOPSIS

Connects to an identity provider, and fixes which provider the session works against

## SYNTAX

### __AllParameterSets

```
Connect-TestEnvironment [-Provider] <string> [-PassThru]
```

## DESCRIPTION

The single entry point for every provider. Naming the provider once here is what lets everything
afterwards - New-TestEnvironment, the report, teardown - be provider-agnostic: they read the active
connection rather than being told again.

Everything except -Provider is mirrored from the provider's own connect command once -Provider is
known, so this function never has to restate what a provider needs.

It was written the other way first, with a parameter set per provider and credential type, and that
broke the moment a second provider arrived. The sets were all Entra's, so 'Connect-TestEnvironment
-Provider AD' - which needs no credentials at all, because Active Directory uses the caller's own
Windows identity - matched the default Entra set and demanded a TenantId, a ClientId and a
certificate thumbprint that do not exist in that world. Reflecting instead means a provider that
needs nothing asks for nothing, and adding a third provider changes no parameters here.

An interactive Entra sign-in is the bootstrap credential, held only to create the service app
that later sessions connect as. When it succeeds, the command checks whether the tenant already
holds that app and whether this machine holds its credential, and prints the next command for the
case it found: connect app-only with the stored credential, create the app, or replace one whose
private key is on another machine.

## EXAMPLES

### Example 1: Imports RSAT, checks elevation and detects the domain

```powershell
Connect-TestEnvironment -Provider AD
```

Output: Nothing, unless -PassThru is supplied

Use case: The normal path on a domain-joined machine

### Example 2: Connects app-only to Entra with a certificate

```powershell
Connect-TestEnvironment -Provider Entra -TenantId <id> -ClientId <c> -CertificateThumbprint <t>
```

Output: Nothing, unless -PassThru is supplied

Use case: The normal path once an Entra service app has been bootstrapped

### Example 3: Signs a human in once so the module can create the app it uses afterwards

```powershell
Connect-TestEnvironment -Provider Entra -TenantId <id> -Interactive
New-TestServiceApp
```

Output: The device code to enter, then the connection

Use case: First run against a new tenant

## PARAMETERS

### -PassThru

{{ Fill PassThru Description }}

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

### -Provider

Which identity provider to connect to. Everything else this command accepts depends on this, so
supply it first when using tab completion.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

### TestEnvironmentConnection

Only when -PassThru is supplied: the connection object the chosen provider returned, naming the tenant, domain or org it resolved and the prefix in force. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Disconnect-TestEnvironment]()
- [Get-TestEnvironmentProvider]()
- [New-TestServiceApp]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
