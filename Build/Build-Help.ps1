#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Microsoft.PowerShell.PlatyPS'; ModuleVersion = '1.0.3' }

<#
.SYNOPSIS
    Validates the PlatyPS help Markdown and compiles it to MAML.

.DESCRIPTION
    One entry point for both the developer loop and CI, so the pipeline cannot validate
    something different from what a person runs locally.

    Validation always runs first and stops on the first failure. It checks five things,
    because each of them fails silently otherwise:

    - Structure, via Test-MarkdownCommandHelp.
    - Unfilled '{{ Fill in' templates. Test-MarkdownCommandHelp checks shape, not whether
      anyone wrote the content, so a file of placeholders passes it.
    - Relative links under RELATED LINKS. Test-MarkdownCommandHelp returns True for these,
      but Get-Help throws 'The specified URI ... is not valid' at read time and returns
      nothing at all for the command.
    - Drift between the documented commands and the exported ones. Stale MAML is worse than
      no MAML: .EXTERNALHELP guarantees a user is shown the stale content rather than
      falling back to anything correct.
    - The .EXTERNALHELP keyword on every exported function, in the file that defines it.
      Exported functions live in Public/ and in each provider's Public/ folder, alongside
      provider commands that are not exported and keep full comment-based help, so the
      check resolves each export to its file rather than sweeping a folder.

    With -ValidateOnly it stops there. Otherwise it compiles the Markdown to
    maml/TestEnvironment/TestEnvironment-Help.xml and copies it into en-US/, which is the
    file Get-Help actually reads and the one every .EXTERNALHELP keyword names.

.PARAMETER ValidateOnly
    Run the checks without rebuilding the MAML. This is what a pull request runs.

.PARAMETER ModuleRoot
    Repository root. Defaults to the parent of the folder holding this script.

.EXAMPLE
    ./Build/Build-Help.ps1

    DESCRIPTION: Validates the Markdown and rebuilds en-US/TestEnvironment-Help.xml
    OUTPUT: A summary line per check and the path of the compiled help file
    USE CASE: The normal developer loop after editing anything under docs/

.EXAMPLE
    ./Build/Build-Help.ps1 -ValidateOnly

    DESCRIPTION: Runs every gate without writing build output
    OUTPUT: Nothing on success; a terminating error naming the first failure
    USE CASE: The pull request check, where the committed help must be proven current

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    The compiled filename carries a capital H - TestEnvironment-Help.xml - because that is
    what Export-MamlCommandHelp produces, while most documentation writes '-help.xml'. On
    Windows the mismatch is invisible; on a case-sensitive filesystem the lookup fails and
    every command silently loses its help. The name is asserted below rather than assumed.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$moduleName = 'TestEnvironment'
$helpFileName = "$moduleName-Help.xml"
$docsPath = Join-Path $ModuleRoot 'docs' $moduleName
$manifest = Join-Path $ModuleRoot "$moduleName.psd1"
$mamlRoot = Join-Path $ModuleRoot 'maml'
$cultureDir = Join-Path $ModuleRoot 'en-US'

if (-not (Test-Path $docsPath)) {
    throw "Help Markdown not found at '$docsPath'. Generate it with New-MarkdownCommandHelp -ModuleInfo (Get-Module $moduleName) -OutputFolder (Split-Path -Parent '$docsPath')."
}

Import-Module $manifest -Force
Import-Module Microsoft.PowerShell.PlatyPS -MinimumVersion 1.0.3

$markdown = Join-Path $docsPath '*.md'

# --- 1. Structure -----------------------------------------------------------------
$structure = Measure-PlatyPSMarkdown -Path $markdown |
    Where-Object Filetype -match 'CommandHelp' |
    Test-MarkdownCommandHelp -Path { $_.FilePath } -DetailView

$invalid = @($structure | Where-Object { -not $_.IsValid })
if ($invalid) {
    $names = ($invalid.Path | Split-Path -Leaf) -join ', '
    throw "Help Markdown failed structure validation: $names"
}
Write-Verbose "Structure: $(@($structure).Count) file(s) valid."

# --- 2. Unfilled templates --------------------------------------------------------
# PlatyPS writes templates, not content. A file still carrying a placeholder is not done.
$unfilled = Select-String -Path $markdown -Pattern '\{\{\s*Fill in|\{\{Insert' -List
if ($unfilled) {
    $names = ($unfilled.Path | Split-Path -Leaf) -join ', '
    throw "Help Markdown still contains placeholders: $names"
}

# --- 3. Relative links ------------------------------------------------------------
# A .LINK value must be a bare topic name or an absolute http/https URL. A relative path
# passes Test-MarkdownCommandHelp and then breaks Get-Help at read time.
#
# The |\) in the lookahead permits a bare topic name, which PlatyPS writes as [Get-Thing]().
# Without it the check rejects every cross-reference between this module's own commands.
$relative = Select-String -Path $markdown -Pattern '^\s*-?\s*\[.+\]\((?!https?://|\))'
if ($relative) {
    $first = $relative | Select-Object -First 1
    throw "Relative link in RELATED LINKS at $($first.Filename):$($first.LineNumber) - use an absolute URL or a bare topic name."
}

# --- 4. Drift against the exported command list -----------------------------------
$documented = (Get-ChildItem (Join-Path $docsPath '*.md')).BaseName |
    Where-Object { $_ -ne $moduleName }
$exported = @((Get-Module $moduleName).ExportedFunctions.Keys)

$missing = @($exported | Where-Object { $_ -notin $documented })
$orphan = @($documented | Where-Object { $_ -notin $exported })

if ($missing) {
    throw "Exported commands with no help Markdown: $($missing -join ', ')"
}
if ($orphan) {
    throw "Help Markdown for commands that are no longer exported: $($orphan -join ', ')"
}

# --- 5. .EXTERNALHELP present and correctly named ---------------------------------
# The keyword is what makes Get-Help read the MAML at all. An exported function missing it
# silently serves its stub synopsis instead, and the compiled help is dead weight.
#
# Resolved per export rather than per folder: the provider Public/ folders also hold the
# connect, seed, report and teardown commands that are reached only through the shared
# dispatchers. Those are not exported, PlatyPS never sees them, and they keep full
# comment-based help - so a folder sweep would demand the keyword where it must not be.
$without = foreach ($name in ($exported | Sort-Object)) {
    $file = (Get-Command -Name $name -Module $moduleName).ScriptBlock.File
    $content = Get-Content -LiteralPath $file -Raw
    if ($content -notmatch [regex]::Escape(".EXTERNALHELP $helpFileName")) {
        $name
    }
}
if ($without) {
    throw "Exported functions missing '.EXTERNALHELP $helpFileName': $($without -join ', ')"
}

Write-Information "All help gates passed ($(@($exported).Count) commands)." -InformationAction Continue

if ($ValidateOnly) {
    return
}

# --- Compile ----------------------------------------------------------------------
Measure-PlatyPSMarkdown -Path $markdown |
    Where-Object Filetype -match 'CommandHelp' |
    Import-MarkdownCommandHelp -Path { $_.FilePath } |
    Export-MamlCommandHelp -OutputFolder $mamlRoot -Force | Out-Null

$built = Join-Path $mamlRoot $moduleName $helpFileName
if (-not (Test-Path $built)) {
    # The output folder may not exist at all - on a fresh checkout maml/ is git-ignored and
    # absent, and it also stays absent if Export-MamlCommandHelp was suppressed. Listing it
    # unguarded throws 'Cannot find path' and buries the actual failure under a message
    # about the diagnostic.
    $outputDir = Join-Path $mamlRoot $moduleName
    $produced = if (Test-Path $outputDir) {
        (Get-ChildItem $outputDir -File).Name -join ', '
    }
    else {
        '(nothing - the output folder was never created)'
    }
    throw "Expected '$helpFileName' but PlatyPS produced: $produced. Every .EXTERNALHELP value must match the produced name exactly, including the capital H."
}

New-Item -Path $cultureDir -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath $built -Destination $cultureDir -Force

$final = Join-Path $cultureDir $helpFileName
Write-Information "Compiled help: $final" -InformationAction Continue
Get-Item -LiteralPath $final
