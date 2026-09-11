---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: ''
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 11 2026
PlatyPS schema version: 2024-05-01
title: New-FreeIPACertificate
---

# New-FreeIPACertificate

## SYNOPSIS

Has the realm's CA issue the seeded certificates from Data\FreeIPACertificates.csv, and revokes the ones the data says are revoked

## SYNTAX

### __AllParameterSets

```
New-FreeIPACertificate [[-CertificateKey] <string[]>] [-PassThru] [-WhatIf] [-Confirm]
```

## DESCRIPTION

Every certificate the seed shows is a real one, issued by the realm's own certificate authority
against a request built here with a throwaway key: user certificates through the IECUserRoles
profile under the seeded CA ACL, service and host certificates through the default service profile.
Each is added to its entry, so a user carries it in userCertificate and the realm's own mapping rule
maps it back to them; and each is recorded by the CA, where a report reads its serial, validity and
status. The rows then make the states a report has to tell apart: a valid certificate on a disabled
account, one revoked for key compromise beside its replacement on the same user, one on certificate
hold, and a service certificate revoked as ceased while the service lives on.

Issuing is not free of consequence: a CA keeps a record of every certificate it ever issued and a
serial number is never reused, so a realm that has been seeded and torn down carries the revoked
serials for good. That is what a real CA does, and it is why teardown revokes rather than pretends
to delete.

A row is satisfied by a certificate that already exists on the principal in the state the row asks
for, so a second run issues nothing it does not need to. A request that the realm refuses - a user
outside every CA ACL, a profile the realm does not have - is recorded against the row and the rest
continue.

## EXAMPLES

### Example 1: Issues every seeded certificate and revokes the ones the data revokes

```powershell
New-FreeIPACertificate
```

Output: None

Use case: Called by New-FreeIPAEnvironment as its last step

### Example 2: Rebuilds the pair on one user, one revoked and one current

```powershell
New-FreeIPACertificate -CertificateKey zmueller-compromised, zmueller-current -PassThru
```

Output: The result object with two certificates

Use case: Testing a report that has to show the live certificate beside the revoked one

### Example 3: Lists the certificates that would be issued without asking the CA for any

```powershell
New-FreeIPACertificate -WhatIf
```

Output: One WhatIf line per row

Use case: Confirming what a shared realm's CA would be asked to sign

## PARAMETERS

### -CertificateKey

Issues only the named rows, by their Key column. Defaults to all of them.

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

Only when -PassThru is supplied: TotalCertificates, Issued, Revoked, Existing, one entry per row under Certificates with its key, principal, serial number, subject, state and expiry, and Errors. No private key is in it; none is kept. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-FreeIPACaAcl]()
- [New-FreeIPACertMapRule]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
