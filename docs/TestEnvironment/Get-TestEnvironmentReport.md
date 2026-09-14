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

Every provider's report takes the same three parameters. -OutputFormat is Console, JSON, CSV or
HTML; -OutputPath is the file to write, or for CSV the folder, and is required for anything but
Console; -PassThru returns the report object as well. A file format puts nothing on the pipeline
without -PassThru. The Entra provider still answers to -Format and -Path, the names it had before.

Every provider returns the same shape: Provider, Target and GeneratedOn, then the facts about the
estate as a whole that only that provider has - a prefix, a licence ceiling, a UPN suffix - then
Counts, one number per section, Sections, the section names in the order they are rendered, and
one property per section holding its rows. The file formats are written by one writer for every
provider, as UTF-8: JSON is the whole object, CSV is a folder with one file per section named
<Provider>Lab<Section>.csv, and HTML is one page with a heading and a table per section. The
console format stays each provider's own, because what a person wants to see differs by directory.

The provider's own parameters are mirrored onto this function at binding time, so provider-specific
switches keep working through it with tab completion and validation intact, and a parameter the
provider does not have fails at binding rather than being quietly dropped.

## EXAMPLES

### Example 1: Runs against the connected provider

```powershell
Get-TestEnvironmentReport
```

Output: The provider's console report

Use case: The normal path, after Connect-TestEnvironment

### Example 2: Writes an HTML report of the seeded estate

```powershell
Get-TestEnvironmentReport -OutputFormat HTML -OutputPath ./test-environment.html
```

Output: The file named, and nothing on the pipeline.

Use case: Handing a picture of the seeded estate to whoever is writing the report the estate exists
to test. The same command works for every provider.

### Example 3: Captures the report as JSON for comparison later

```powershell
$report = Get-TestEnvironmentReport -OutputFormat JSON -OutputPath ./test-environment.json -PassThru
$report.Counts
```

Output: The report object, and the same content written to the file.

Use case: Diffing the estate before and after a change. Counts is one number per section for every
provider, so a script that checks it does not care which directory is connected.

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

The report object, when -PassThru is requested: Provider, Target, GeneratedOn, the provider's own
facts, Counts, Sections, and one property per section. Otherwise the report is written to the console
or to the file named, and nothing reaches the pipeline.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-TestEnvironment]()
- [Remove-TestEnvironment]()
- [about_TestEnvironment]()
