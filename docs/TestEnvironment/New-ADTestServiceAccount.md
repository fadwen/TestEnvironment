---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-ADTestServiceAccount.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-ADTestServiceAccount
---

# New-ADTestServiceAccount

## SYNOPSIS

Creates Active Directory test service accounts from CSV data

## SYNTAX

### __AllParameterSets

```
New-ADTestServiceAccount [[-VaultName] <string>] [[-VaultPassword] <securestring>] [-PassThru]
 [-UseSecretStore] [-GlobalVault] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Creates service accounts in Active Directory based on data from ADServiceAccounts.csv. Service
accounts are created with secure passwords, configured for non-interactive use.

Passwords are generated and returned in the results object for external handling (e.g., file export
or SecretStore storage by calling functions).

## EXAMPLES

### Example 1: Creates all service accounts from ADServiceAccounts.csv and displays summary

```powershell
New-ADTestServiceAccount
```

### Example 2: Creates service accounts and stores passwords securely in the ADTestEnvironment vault

```powershell
New-ADTestServiceAccount -UseSecretStore
```

### Example 3: Creates service accounts and stores passwords in a global vault (requires admin privileges)

```powershell
New-ADTestServiceAccount -UseSecretStore -GlobalVault
```

### Example 4: Creates service accounts and returns results object with password data

```powershell
$results = New-ADTestServiceAccount -PassThru
```

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

### -GlobalVault

Create SecretStore vault at AllUsers scope instead of CurrentUser scope. Requires administrative
privileges. Only applies when UseSecretStore is specified.

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

### -PassThru

Returns the results object instead of displaying summary

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

### -UseSecretStore

Use PowerShell SecretManagement/SecretStore modules to store passwords in a secure vault. When
specified, triggers SecretStore orchestration after account creation.

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

### -VaultName

Name of the secret vault to use when UseSecretStore is specified. Defaults to "ADTestEnvironment"

```yaml
Type: System.String
DefaultValue: ADTestEnvironment
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

### -VaultPassword

Password for the secret vault when UseSecretStore is specified. If not provided, will use
"ADTestEnvironmentPassword" as the default to avoid prompting.

```yaml
Type: System.Security.SecureString
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

Only when -PassThru is supplied: creation results and statistics. Unless -UseSecretStore diverted them to the vault, the generated passwords are included, so treat the object accordingly.

## NOTES

Author: Jeffrey Stuhr

SecretStore Features:
- Use -UseSecretStore to store passwords in an encrypted vault instead of plain text files
- Automatically installs required SecretManagement/SecretStore modules if not present
- Creates computer-level vault for shared access (when run as administrator)
- Retrieve passwords later using Get-ADTestPasswordFromVault function

## RELATED LINKS

- [Get-ADTestPasswordFromVault]()
- [New-ADTestOUStructure]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
