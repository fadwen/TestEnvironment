---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Get-TestEnvironmentRuntime.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 16 2026
PlatyPS schema version: 2024-05-01
title: Get-TestEnvironmentRuntime
---

# Get-TestEnvironmentRuntime

## SYNOPSIS

Reports which PowerShell the module is running on and which methods it is using because of it.

## SYNTAX

### __AllParameterSets

```
Get-TestEnvironmentRuntime [<CommonParameters>]
```

## DESCRIPTION

The module runs on Windows PowerShell 5.1, because a freshly built domain controller has nothing
else, and on PowerShell 7.4, which the REST providers are better served by. It detects the
difference once at import and picks its methods from what the running PowerShell supports, not from
a version number: a parameter that exists on Invoke-WebRequest is one that works. This command shows
that decision, so a run that behaves differently on two hosts can be explained by the first line of
its output.

Edition and Version are what $PSVersionTable says. Preferred says whether this is the PowerShell
the module is best run on, and Recommendation says so in a sentence: PowerShell 7.4 or later is
preferred for every provider; Windows PowerShell 5.1 is supported because a freshly built domain
controller has nothing else. Capability holds one boolean per detected
feature. Http says what the HTTP layer does with them: how the body of a failed response is read and
whether TLS 1.2 had to be added. The encoding and the progress handling are the same on both editions
and are listed so the object is complete. Parallel names the mechanism the seed steps run several
objects at a time on, which is the same runspace pool on both. HTTP/2 is not among the decisions: it
was tried on PowerShell 7.3 and measured no faster, so it is not requested.

## EXAMPLES

### Example 1: Shows the running PowerShell and the methods chosen for it

```powershell
Get-TestEnvironmentRuntime
```

Output: Edition, Version, Platform, Preferred, Recommendation, Capability, Http and Parallel.

Use case: The first thing to include when reporting a run that behaved differently on two hosts.

### Example 2: Shows only the HTTP decisions

```powershell
(Get-TestEnvironmentRuntime).Http
```

Output: ErrorBody SkipHttpErrorCheck and Tls Default on PowerShell 7.4; ResponseStream and
Tls12Added on Windows PowerShell.

Use case: Confirming that a host is getting the PowerShell 7 paths.

### Example 3: Branches a script on a detected capability rather than on a version

```powershell
if (-not (Get-TestEnvironmentRuntime).Capability.SkipHttpErrorCheck) {
    Write-Warning 'Windows PowerShell: the REST providers work, but 7.4 is faster.'
}
```

Output: A warning on Windows PowerShell, nothing on PowerShell 7.

Use case: A lab script that runs on both.

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

### TestEnvironmentRuntime

Edition, Version and Platform; Preferred and Recommendation; Capability with SkipHttpErrorCheck,
HttpTimeouts, JsonAsHashtable, ModernTls and NativeUtf8; Http with ErrorBody, Tls, Encoding and
Progress; and Parallel.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Connect-TestEnvironment]()
- [about_TestEnvironment]()
