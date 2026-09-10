---
document type: cmdlet
external help file: TestEnvironment-Help.xml
HelpUri: https://github.com/fadwen/TestEnvironment/blob/main/docs/TestEnvironment/New-EntraDirectoryExtension.md
Locale: en-US
Module Name: TestEnvironment
ms.date: 09 09 2026
PlatyPS schema version: 2024-05-01
title: New-EntraDirectoryExtension
---

# New-EntraDirectoryExtension

## SYNOPSIS

Creates custom directory extension attributes and populates them

## SYNTAX

### __AllParameterSets

```
New-EntraDirectoryExtension [[-ExtensionKey] <string[]>] [-SkipValues] [-ShowProgress] [-PassThru]
 [-WhatIf] [-Confirm]
```

## DESCRIPTION

This is the Entra counterpart to Okta's custom profile attributes, and it is the part of a cloud
directory that scripts written against the built-in schema never see.

Ten attributes are created on a dedicated schema application, chosen for **type coverage rather than
realism** - a schema of nothing but strings will not tell you that your export flattens a binary
value or that a 64-bit integer lost precision on the way through a double. All six data types Graph
accepts are represented, verified against a live tenant: String, Boolean, Integer, LargeInteger,
DateTime and Binary.

Three things make these genuinely different from the `extensionAttribute1-15` the module already
uses as a seed tag, and all three are worth knowing:

- **They are filterable.** Verified live: a directory extension can be used in `$filter`
  and returns the right user, where `extensionAttribute15`, `employeeType` and
  `companyName` are all rejected with `Request_UnsupportedQuery`.
That makes an
  extension the only writable, queryable marker on a user.
- **They can target objects other than users.** Two of the ten sit on groups and devices,
  which Okta's profile attributes cannot do at all.
- **They are namespaced to the application that owns them.** The real property name is
  `extension_<appId-without-dashes>_<name>`, so the same short name on two apps is two
  different attributes.
Deleting the owning application takes the attributes and every
  value stored in them with it.

What they cannot do is worth stating too, because Okta can: there is **no enum type** and **no
multi-valued type**. Okta's `labClearanceLevel` is validated against a list and its
`labEntitlements` holds an array; the nearest directory extension is an unconstrained single string.
Anything needing either has to reach for custom security attributes instead, which need a role a
Global Administrator does not hold by default.

## EXAMPLES

### Example 1: Creates the schema application, its ten attributes, and populates them

```powershell
New-EntraDirectoryExtension
```

Output: None

Use case: Called by New-EntraEnvironment

### Example 2: Shows the short names and the namespaced names Graph actually stores

```powershell
New-EntraDirectoryExtension -PassThru | Select-Object Name, PropertyName
```

Output: labSeedTag -> extension_a1b2..._labSeedTag

Use case: Working out what to put in a $select or $filter

### Example 3: Defines two attributes without populating them

```powershell
New-EntraDirectoryExtension -ExtensionKey seedtag, clearance -SkipValues
```

Output: None.

Use case: Testing what an export does with an extension attribute that exists but is empty on every
object.

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

### -ExtensionKey

Creates only the named extensions, by their Key column. Defaults to all of them.

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

Returns the created extensions

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

### -ShowProgress

Draws a progress bar

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

### -SkipValues

Creates the attribute definitions but writes no values onto seeded objects

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

### EntraDirectoryExtension

One object per extension attribute created, only when -PassThru is supplied. Nothing is written to the pipeline otherwise.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [New-EntraUser]()
- [New-EntraGroup]()
- [New-TestEnvironment]()
- [about_TestEnvironment]()
