---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/Compare-TestEnvironment.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 14 2026
PlatyPS schema version: 2024-05-01
title: Compare-TestEnvironment
---

# Compare-TestEnvironment

## SYNOPSIS

Compares the people two connected providers hold, the way a hybrid identity match would

## SYNTAX

### __AllParameterSets

```
Compare-TestEnvironment [-Provider] <string[]> [-Quiet]
```

## DESCRIPTION

The seed puts the same people into every directory it knows - the nine written in other writing
systems, the nine core people, the bulk of the Active Directory data mapped into Entra, Authentik,
FreeIPA and PingOne - so that whatever matches identities across two directories can be tested
against them. This reads the seeded people from two providers connected in this session and reports
how they line up.

People are matched by login key first - the login with the provider's additions stripped, so jnino
is jnino in every provider that keeps the shared logins - and then by display name among what is
left, because the Active Directory data logs its people in as first name and initial and agrees
with the others only on the names. The name match folds case and Unicode normalisation, so a name
one directory stored decomposed still finds its person, and the codepoint difference is then
reported as the finding it is. What matches in neither way is reported as only on one side; that is
not a fault, because the providers hold deliberately different populations, and the report says so
rather than judging it.

For every matched pair the names are compared by codepoint, never with -eq, which calls a
decomposed and a precomposed name equal: display names where both providers keep one, otherwise the
given name and surname where both keep those - so a tenant is compared with a PingOne environment,
which stores no display name, on the parts - and never a stored display name against one composed
from parts, which would call every family-name-first person a mismatch. A person whose name differs
between two directories is the finding a hybrid match would trip over, and it is the one thing this
command judges. Whether the account is enabled is compared and reported without a verdict, because
the seed hangs different states on the same person in different providers on purpose.

Both providers must be connected in this session. Connect-TestEnvironment keeps one active for the
other commands, but every provider keeps its own connection, so connecting to a second does not drop
the first.

## EXAMPLES

### Example 1: Compares a tenant with a PingOne environment

```powershell
Connect-TestEnvironment -Provider Entra -TenantId $tenant -UseStoredCredential
Connect-TestEnvironment -Provider PingOne -EnvironmentId $environment -ClientId $client -UseStoredCredential
Compare-TestEnvironment -Provider Entra, PingOne
```

Output: The counts on each side, how many matched by key and by name, who is only on one side, whose
enabled state differs, and whether every matched name agrees.

Use case: Proving that the two directories a hybrid identity tool is about to match hold the same
people under the same names.

### Example 2: Lists the people one side holds and the other does not

```powershell
(Compare-TestEnvironment -Provider AD, Entra -Quiet).OnlyRight
```

Output: One line per person, as key and display name.

Use case: The Entra data carries core people the Active Directory data does not; this names them.

## PARAMETERS

### -Provider

The two providers to compare, as Get-TestEnvironmentProvider names them.

```yaml
Type: System.String[]
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

### -Quiet

Return the result without writing to the console.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### TestEnvironmentComparison

Left and Right, each with Provider, Target and Count; Matched, MatchedByKey, MatchedByName and
NamesCompared; OnlyLeft, OnlyRight, NameMismatch and StateDifference as lists; and Passed, which is
$true when every matched pair's names agree.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Connect-TestEnvironment]()
- [Test-TestEnvironment]()
- [Get-TestEnvironmentReport]()
- [about_TestEnvironment]()
