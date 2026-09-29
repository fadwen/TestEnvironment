---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-OneLoginAppCredential.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 29 2026
PlatyPS schema version: 2024-05-01
title: Get-OneLoginAppCredential
---

# Get-OneLoginAppCredential

## SYNOPSIS

Returns the saved client id and secret of seeded OneLogin apps as credentials

## SYNTAX

### __AllParameterSets

```
Get-OneLoginAppCredential [[-Key] <string[]>] [[-Subdomain] <string>]
 [[-VaultPassword] <securestring>]
```

## DESCRIPTION

Reads back the client secrets New-OneLoginApp -SaveAppSecret saved, one credential per app, so a relying party can be configured to sign in through a seeded app. The client id is the credential's user name and the secret its password; the secret is never written to the pipeline as text.

Only the apps created with -SaveAppSecret have a record, and only the ones that authenticate with a secret: Expenses Web, which sends it with HTTP Basic, and Payroll Console, which posts it in the body. The public and native clients and the SAML app have no secret to save. OneLogin shows an app's secret once, when the app is created, so an app that already existed when the seed ran has no record; delete it and seed again, or regenerate its secret in the portal.

The seeded apps' redirect URLs are under the lab email domain, example.com by default, so a test client has to be reachable there - a hosts entry, or the connection's -EmailDomain set to a domain you control - or have its own redirect URL added to the app in the portal. The client credentials grant is not enabled on the seeded apps; a token request made with it is refused.

A secret saved in the SecretStore is read from the vault, which may need its password.

Remove-TestEnvironment deletes each record with its app, and any record whose app is no longer in the account.

## EXAMPLES

### Example 1: List every saved app credential

```powershell
Get-OneLoginAppCredential
```

DESCRIPTION: Lists every saved app credential for the connected account
OUTPUT: One object per app, the secret held in a PSCredential
USE CASE: Seeing which seeded apps have a saved secret

### Example 2: Copy one app's secret

```powershell
$app = Get-OneLoginAppCredential -Key expenses
$app.Credential.GetNetworkCredential().Password | Set-Clipboard
```

DESCRIPTION: Copies the Expenses Web client secret to the clipboard
OUTPUT: None
USE CASE: Pasting the secret into a test client that signs in to the seeded app

### Example 3: See which apps have a saved secret, and how it is protected

```powershell
Get-OneLoginAppCredential | Select-Object Key, Name, AppId, Protection
```

DESCRIPTION: Lists the saved apps without touching the secrets
OUTPUT: One row per app - expenses and payroll after a seed with -SaveAppSecret - with DPAPI or SecretStore
USE CASE: Checking what a seed left on this machine before handing it to somebody else

## PARAMETERS

### -Key

Return only the apps with these keys from the seed data, such as expenses. Every saved app by default.

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

### -Subdomain

The account whose saved secrets to read. The connected account by default.

```yaml
Type: System.String
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

### -VaultPassword

The SecretStore vault's password, when a secret is kept there and the vault is not the module default.

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

One object per saved app with Key, Name, AppId, Subdomain, Protection and Credential, a PSCredential whose user name is the client id and whose password is the client secret. The secret is never on the pipeline as text.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/


## RELATED LINKS

- [New-OneLoginApp]()
