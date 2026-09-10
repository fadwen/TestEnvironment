---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-ADTestPasswordFromVault.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Get-ADTestPasswordFromVault
---

# Get-ADTestPasswordFromVault

## SYNOPSIS

Retrieves a stored password from the ADTestEnvironment SecretStore vault

## SYNTAX

### ByServiceAccount (Default)

```
Get-ADTestPasswordFromVault -ServiceAccountName <string> [-VaultName <string>] [-AsPlainText]
 [-IncludeExpired]
```

### BySecretName

```
Get-ADTestPasswordFromVault -SecretName <string> [-VaultName <string>] [-AsPlainText]
 [-IncludeExpired]
```

### ListSecrets

```
Get-ADTestPasswordFromVault [-VaultName <string>] [-AsPlainText] [-ListSecrets] [-IncludeExpired]
```

## DESCRIPTION

Helper function to retrieve passwords that were stored using Export-ADTestPasswordDocumentation with
the -UseSecretStore parameter. Can retrieve by service account name or secret name.

## EXAMPLES

### Example 1: Retrieves the most recent password for svc-app1 as a SecureString

```powershell
Get-ADTestPasswordFromVault -ServiceAccountName "svc-app1"
```

### Example 2: Retrieves the password as plain text (use with caution)

```powershell
Get-ADTestPasswordFromVault -ServiceAccountName "svc-app1" -AsPlainText
```

### Example 3: Lists all stored secrets with their metadata

```powershell
Get-ADTestPasswordFromVault -ListSecrets
```

### Example 4: Lists all secrets including expired ones

```powershell
Get-ADTestPasswordFromVault -ListSecrets -IncludeExpired
```

## PARAMETERS

### -AsPlainText

Return the password as plain text instead of SecureString. Use with caution.

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

### -IncludeExpired

Include expired secrets in results (based on ExpirationDate metadata)

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

### -ListSecrets

List all secrets in the vault with their metadata

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ListSecrets
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SecretName

Exact name of the secret in the vault (includes timestamp)

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: BySecretName
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ServiceAccountName

Name of the service account to retrieve the password for

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ByServiceAccount
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -VaultName

Name of the secret vault to search. Defaults to "ADTestEnvironment"

```yaml
Type: System.String
DefaultValue: ADTestEnvironment
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### System.Security.SecureString

The most recent password stored for the account, by default.

### System.String

The same password in plain text, when -AsPlainText is supplied.

### System.Management.Automation.PSObject

With -ListSecrets, one object per stored secret carrying its name and metadata rather than the password itself.

## NOTES

Author: Jeffrey Stuhr

Security Notes:
- Use -AsPlainText sparingly and ensure secure handling
- SecureString return type is recommended for production use
- Expired passwords are filtered out by default

## RELATED LINKS

- [New-ADTestServiceAccount]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
