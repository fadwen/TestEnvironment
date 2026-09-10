---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-TestEnvironmentReport.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: Get-TestEnvironmentReport
---

# Get-TestEnvironmentReport

## SYNOPSIS

Reports what is currently seeded through the active provider

## SYNTAX

### __AllParameterSets

```
Get-TestEnvironmentReport
```

## DESCRIPTION

Dispatches to the provider the session is connected through, which was fixed by
Connect-TestEnvironment. The provider is deliberately not a parameter here: naming it again on every
call is how a script ends up seeding one directory and tearing down another, and the connection
already knows the answer.

The provider's own parameters are mirrored onto this function at binding time, so provider-specific
switches keep working through it with tab completion and validation intact, and a parameter the
provider does not have fails at binding rather than being quietly dropped.

## EXAMPLES

### Example 1: Runs against the connected provider

```powershell
Get-TestEnvironmentReport
```

Output: The provider's own result

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Writes an HTML report of a seeded Entra tenant

```powershell
Get-TestEnvironmentReport -Format Html -Path ./entra-test-environment.html
```

Output: The file named, and nothing on the pipeline.

Use case: Handing a picture of the seeded estate to whoever is writing the report the estate exists
to test. -Format and -Path are the Entra provider's parameters, mirrored here.

### Example 3: Captures the AD or Okta report as JSON for comparison later

```powershell
Get-TestEnvironmentReport -OutputFormat JSON -OutputPath ./ad-test-environment.json -PassThru
```

Output: The report object, and the same content written to the file.

Use case: Diffing the estate before and after a change. The AD and Okta providers name these
parameters -OutputFormat and -OutputPath, which is what tab completion shows once they are active.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### TestEnvironmentReport

The provider's report object when an object format or -PassThru is requested. Otherwise the report is written to the console or to the file named, and nothing reaches the pipeline.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
