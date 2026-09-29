---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-OneLoginApp.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 29 2026
PlatyPS schema version: 2024-05-01
title: New-OneLoginApp
---

# New-OneLoginApp

## SYNOPSIS

Creates the seeded OIDC and SAML apps and grants them to their roles

## SYNTAX

### __AllParameterSets

```
New-OneLoginApp [[-Key] <string[]>] [[-Tier] <string[]>] [[-VaultPassword] <securestring>]
 [-SaveAppSecret] [-UseSecretStore] [-PassThru] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Five apps, because a OneLogin trial allows five, across the two protocols and every OpenID Connect client shape the generic connector offers:

- Expenses Web, a confidential web client authenticating with HTTP Basic, granted to All Staff.
- Payroll Console, a confidential web client that posts its secret in the body, granted to Finance, whose audience a mapping widens.
- Contractor Portal SPA, a public client. On OneLogin a public client is chosen by token endpoint authentication None, and that is PKCE: the connector offers no public client without it.
- Field App, a native client with a custom-scheme redirect, hidden from the portal and granted to no role, which an inventory still has to list and a review still has to explain.
- Wiki SAML, a SAML app built on the SAML Custom Connector (Advanced), so anything that assumes every app has a client id has one that does not. It is granted to two roles.

The description carries the seed tag inside a sentence - "Seeded by TestEnvironment. Safe to delete." - so an administrator who finds one in a production portal knows what made it. Teardown requires the tag in the description and the prefix on the name together. A prefixed app that already exists without the tag is left alone and granted to nothing.

OneLogin returns a new app's client secret in the response to its creation, and no later read of the app returns it. By default only the id is kept and the secret is dropped: nothing in the module needs it. With -SaveAppSecret, the secrets of the two confidential clients created in this run - Expenses Web and Payroll Console - are kept, DPAPI-protected in a record under ~/.testenvironment or in a SecretStore vault with -UseSecretStore, and Get-OneLoginAppCredential reads them back as credentials. Remove-TestEnvironment deletes each saved secret with its app, and any whose app is no longer in the account, so they do not build up.

Every URL is written against the connection's email domain, under example.com by default, never a real host.

Apps are granted to roles here, one request per role, and only to roles the seed may use: its own, or an empty one of its names. What a role already holds is read and kept, because the endpoint sets a role's apps rather than adding to them.

## EXAMPLES

### Example 1: Create every seeded app

```powershell
New-OneLoginApp
```

DESCRIPTION: Creates the five apps and grants them to their roles
OUTPUT: None
USE CASE: Run for you by New-TestEnvironment, once the roles exist

### Example 2: Create the SAML app alone

```powershell
New-OneLoginApp -Key wiki-saml -PassThru
```

DESCRIPTION: Creates Wiki SAML and grants it to All Staff and Contractors
OUTPUT: A result object with its id and the grants applied - never a secret
USE CASE: Testing how a tool handles an app with no client id

### Example 3: Preview in an account you care about

```powershell
New-OneLoginApp -WhatIf
```

DESCRIPTION: Shows every app and grant that would be made, making none
OUTPUT: A What if: line per app and per role granted to
USE CASE: Checking the seed fits under the account's app limit before it runs

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

Create only the rows with these keys, from the seed data file. All of them by default.
Create only the rows with these keys, from the seed data file.
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

Return a result object describing what was created, reused and refused.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

### -SaveAppSecret

Keep the client secret of each confidential app this run creates - Expenses Web and Payroll Console - protected, so a sign-in can be tested against it with Get-OneLoginAppCredential. Off by default: nothing in the module needs the secrets.

OneLogin shows an app's secret only in the answer to its creation, so an app that already existed has none to save; it is named in SecretsUnavailable and a warning. The public and native clients and the SAML app have no secret. Remove-TestEnvironment deletes each saved secret with its app.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

### -Tier

Grant apps only to the roles the chosen tiers create. Both tiers by default. With -Tier Bulk alone no role is created, so the apps are created and granted to nothing.
Grant apps only to the roles the chosen tiers create.
Both tiers by default.
With -Tier Bulk alone no role is created, so the apps are created and granted to nothing.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseSecretStore

With -SaveAppSecret, keep the secrets in a SecretStore vault rather than DPAPI-protected in their records under ~/.testenvironment.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
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

### -VaultPassword

With -UseSecretStore, the vault's password when it is not the module default.

```yaml
Type: System.Security.SecureString
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
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

Only when -PassThru is supplied: a summary with TotalApps, CreatedApps, ReusedApps, GrantsApplied, Apps and Errors. Apps carries each app's key, name, id and connector, and never a client secret. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-OneLoginRole]()
- [New-OneLoginUser]()
