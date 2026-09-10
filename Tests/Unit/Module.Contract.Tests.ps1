#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the module itself - manifest, exports and layout.

    Each corresponds to a defect that shows up in modules of this shape: a function exported
    from the root module but absent from the manifest, which exports nothing and fails only
    when somebody calls it; two files holding three functions between them; a private helper
    that shadows a cmdlet. They are cheap, they need no tenant, and they catch the class of
    mistake that is invisible until the module is in use.

    These assertions are provider-agnostic and live at the root of the test tree. Anything true
    of only one provider - the shape of its seed data, the objects it can create - belongs
    under Providers/<name>, beside the provider it describes.

    There are no stubs to load. This module declares no RequiredModules and calls nothing
    absent from a stock host, so it imports on a bare CI runner as-is.
#>

BeforeDiscovery {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

    # Every folder that may hold function files, including each provider's own. Discovered
    # rather than listed, so a provider added later is covered by these assertions the moment
    # its folder exists rather than whenever somebody remembers to name it here.
    $script:FunctionFolder = @(
        (Join-Path $script:ModuleRoot 'Core')
        (Join-Path $script:ModuleRoot 'Public')
        foreach ($provider in (Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Providers') -Directory -ErrorAction SilentlyContinue)) {
            (Join-Path $provider.FullName 'Private')
            (Join-Path $provider.FullName 'Public')
        }
    ) | Where-Object { Test-Path -LiteralPath $_ }

    # Built at discovery time so each file gets its own -ForEach case and a failure names the
    # file rather than burying it in one aggregate assertion. The path is carried rather than
    # the bare file name, because a name no longer identifies a file uniquely once providers
    # exist, and a failure that cannot be traced to one file is half a result.
    $script:FunctionFile = @(
        Get-ChildItem -Path $script:FunctionFolder -Filter *.ps1 -ErrorAction SilentlyContinue |
            ForEach-Object {
                @{
                    Name     = $_.FullName.Substring($script:ModuleRoot.Length).TrimStart('\', '/')
                    FullName = $_.FullName
                    BaseName = $_.BaseName
                }
            }
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:Manifest = Join-Path $script:ModuleRoot 'TestEnvironment.psd1'

    Import-Module $script:Manifest -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Module manifest' -Tag 'Unit', 'Contract' {

    It 'is a valid manifest' {
        # Pester 6 has no Should-Not-Throw. Running the command is the assertion: anything it
        # throws fails the test, with the real error rather than a wrapped one.
        $manifestData = Test-ModuleManifest -Path $script:Manifest -ErrorAction Stop
        $manifestData.Name | Should-Be 'TestEnvironment'
    }

    It 'declares both editions it claims to support' {
        $data = Import-PowerShellDataFile -Path $script:Manifest
        $data.CompatiblePSEditions | Should-BeCollection @('Desktop', 'Core')
    }

    It 'declares no required modules' {
        # The zero-dependency stance is what lets one module serve providers that do not share
        # a platform. A RequiredModules entry appearing here means somebody declared the AD
        # provider's RSAT dependency - or reached for the Graph SDK - and the module now needs
        # an install on every host that imports it, whichever provider it was going to use.
        $data = Import-PowerShellDataFile -Path $script:Manifest
        @($data.RequiredModules).Count | Should-Be 0
    }

    It 'exports exactly what the root module exports' {
        # A name in one list and not the other is invisible until somebody calls it. The root
        # module's list is read from its AST rather than by regex, so a name in a comment or a
        # verbose message cannot be mistaken for an export.
        $fromManifest = @((Import-PowerShellDataFile -Path $script:Manifest).FunctionsToExport) | Sort-Object

        $rootModulePath = Join-Path $script:ModuleRoot 'TestEnvironment.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($rootModulePath, [ref]$null, [ref]$null)
        $exportCall = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Export-ModuleMember'
                }, $true))

        $exportCall.Count | Should-Be 1

        # Skip the first command element: it is the literal 'Export-ModuleMember', which
        # matches the verb-noun shape as readily as anything it exports. The search is
        # recursive because @(...) parses to an array expression wrapping the literal, not to
        # the literal itself.
        $fromRootModule = @(@($exportCall[0].CommandElements) | Select-Object -Skip 1 | ForEach-Object {
                $_.FindAll({
                        param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true)
            } | ForEach-Object { $_.Value } | Where-Object { $_ -match '^[A-Za-z]+-[A-Za-z]+$' }) |
            Sort-Object -Unique

        $missing = @($fromManifest | Where-Object { $fromRootModule -notcontains $_ })
        $extra = @($fromRootModule | Where-Object { $fromManifest -notcontains $_ })

        "$($missing -join ',')|$($extra -join ',')" | Should-Be '|'
    }

    It 'exports every function it says it does' {
        $declared = @((Import-PowerShellDataFile -Path $script:Manifest).FunctionsToExport) | Sort-Object
        $actual = @((Get-Command -Module TestEnvironment).Name) | Sort-Object
        $actual | Should-BeCollection $declared
    }

    It 'exports only approved verbs' {
        $unapproved = @(
            foreach ($command in (Get-Command -Module TestEnvironment)) {
                if ($command.Verb -notin (Get-Verb).Verb) { $command.Name }
            }
        )
        $unapproved | Should-BeCollection @()
    }
}

Describe 'Provider discovery' -Tag 'Unit', 'Contract' {

    It 'discovers every provider folder on disk' {
        # Providers are found by looking rather than by a list in code, so this proves the
        # looking works rather than that somebody kept a list current.
        $onDisk = @((Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Providers') -Directory).Name) | Sort-Object
        $discovered = @((Get-TestEnvironmentProvider).Name) | Sort-Object

        # Joined rather than compared as collections. Piping one item unrolls it to a scalar
        # that Should-BeCollection refuses, and comma-wrapping to avoid that then double-wraps
        # once a second provider exists. A joined string is correct at any count, and names the
        # providers on both sides when it fails.
        ($discovered -join ', ') | Should-Be ($onDisk -join ', ')
    }

    It 'gives every provider seed data' {
        # A provider whose Data folder is empty loads cleanly and then seeds nothing, reporting
        # success the whole way.
        foreach ($provider in (Get-TestEnvironmentProvider)) {
            $provider.SeedFiles | Should-BeGreaterThan 0
        }
    }

    It 'has no provider active before anything connects' {
        # The dispatchers refuse to run without an active provider, which only protects anybody
        # if a freshly imported module really has none.
        @(Get-TestEnvironmentProvider | Where-Object Active).Count | Should-Be 0
    }

    It 'offers every discovered provider to Connect-TestEnvironment' {
        # -Provider is validated against a fixed set, because a typo should fail at binding
        # rather than after a token has been fetched. That set has to keep pace with the
        # folders on disk, and nothing but this notices when it stops doing so.
        $validate = @((Get-Command Connect-TestEnvironment).Parameters['Provider'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })

        $validate.Count | Should-Be 1
        (@($validate[0].ValidValues | Sort-Object) -join ', ') |
            Should-Be (@((Get-TestEnvironmentProvider).Name | Sort-Object) -join ', ')
    }
}

Describe 'Module layout' -Tag 'Unit', 'Contract' {

    It '<Name> defines exactly one function' -ForEach $script:FunctionFile {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$null)
        $functions = @($ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))

        $functions.Count | Should-Be 1
    }

    It '<Name> defines a function matching its file name' -ForEach $script:FunctionFile {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$null)
        $functions = @($ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))

        $functions[0].Name | Should-Be $BaseName
    }

    It '<Name> parses without error' -ForEach $script:FunctionFile {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$errors)
        @($errors).Count | Should-Be 0
    }

    It '<Name> shadows no existing cmdlet' -ForEach $script:FunctionFile {
        # A private helper called Get-Content would be loaded ahead of the real one for every
        # other function in the module, and nothing would say so.
        $conflicting = Get-Command -Name $BaseName -CommandType Cmdlet -ErrorAction SilentlyContinue
        $conflicting | Should-BeFalsy
    }

    It 'defines each function name exactly once across every provider' {
        # Providers are dot-sourced in folder order into one session state, so two of them
        # defining the same function name means the second silently wins and the first
        # provider's callers get an implementation aimed at another directory. Nothing about
        # that is visible at import: it loads cleanly and then misbehaves against a live
        # tenant. This is the cost of one module rather than three, and this is the check
        # that pays it.
        $duplicate = @(
            $script:FunctionFile | Group-Object BaseName | Where-Object Count -gt 1 |
                ForEach-Object { $_.Name }
        )

        $duplicate | Should-BeCollection @()
    }

    It 'leaves no function files loose at the module root' {
        # The root module dot-sources Core, Providers and Public by name, so a .ps1 sitting
        # beside the manifest is never loaded. It still looks authoritative to anybody reading
        # the folder, and an edit made to it changes nothing at all - which is precisely what
        # happened when these dispatchers were first moved into Public and stale copies stayed
        # behind. The layout assertions above could not see them, because they only look where
        # the module actually loads from.
        # Piped rather than property-accessed: .Name on an empty result yields $null, and
        # @($null) is a one-item collection that would fail this for the wrong reason. Joined
        # rather than compared as a collection so the failure names the stray files, which is
        # the entire question being asked.
        $loose = @(Get-ChildItem -Path $script:ModuleRoot -Filter *.ps1 -File | ForEach-Object Name)
        ($loose -join ', ') | Should-Be ''
    }

    It 'assigns every script-scope variable that any function reads' {
        # The bug this exists for: each provider used to be its own module, and each root module
        # declared the module-scope constants its functions read. Consolidating copied Private,
        # Public and Data - and left one constant behind. Nothing failed at import. The function
        # that read it did "$row.Url -replace [regex]::Escape($null), $domain", and replacing an
        # empty pattern inserts the replacement between every character rather than erroring, so
        # an app was created with a mangled URL and the run reported success.
        #
        # Reads and assignments are both taken from the AST, so a name in a comment or a string
        # counts as neither.
        # Enumerated here rather than reused from BeforeDiscovery. Discovery and run are
        # separate scopes in Pester 5 and later, so $script:FunctionFolder is empty by the time
        # an It block executes - and Get-ChildItem over nothing finds no reads, which makes this
        # assertion pass while checking nothing at all. That is exactly how it behaved when
        # first written, and only re-running it against the real defect showed it up.
        $files = @(
            Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Core') -Filter *.ps1 -ErrorAction SilentlyContinue
            Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public') -Filter *.ps1 -ErrorAction SilentlyContinue
            Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Providers') -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue
            Get-Item -Path (Join-Path $script:ModuleRoot 'TestEnvironment.psm1')
        )

        # A guard on the guard: if the enumeration ever comes back empty again, fail loudly
        # rather than silently reporting no orphans.
        $files.Count | Should-BeGreaterThan 50

        $read = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $assigned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

            foreach ($variable in $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $node.VariablePath.IsScript
                    }, $true)) {
                $null = $read.Add($variable.VariablePath.UserPath)
            }

            # Assignment covers '=', the compound forms like '+=', and ++/-- - all of which
            # establish the variable as this module's to own.
            foreach ($assignment in $ast.FindAll({
                        param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]
                    }, $true)) {
                if ($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $assignment.Left.VariablePath.IsScript) {
                    $null = $assigned.Add($assignment.Left.VariablePath.UserPath)
                }
            }

            foreach ($unary in $ast.FindAll({
                        param($node) $node -is [System.Management.Automation.Language.UnaryExpressionAst]
                    }, $true)) {
                if ($unary.Child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $unary.Child.VariablePath.IsScript) {
                    $null = $assigned.Add($unary.Child.VariablePath.UserPath)
                }
            }
        }

        $orphaned = @($read | Where-Object { -not $assigned.Contains($_) } | Sort-Object)
        ($orphaned -join ', ') | Should-Be ''
    }

    It 'never reaches into module scope from inside a background job' {
        # A Start-Job script block runs in a fresh runspace. Module scope does not travel there,
        # so $script:Anything is empty and any module function is undefined - and neither fails
        # loudly. An empty string interpolated into a distinguished name produces
        # 'OU=Users,OU=,DC=contoso,DC=com', which AD rejects per object while the run carries on.
        #
        # That is not hypothetical. Prefixing the AD provider's objects put $script:ADTestRootName
        # inside two job bodies; the live run created 688 computers with no prefix and silently
        # failed to create all 296 users. The unit tests mock above the job boundary and saw
        # nothing wrong. Values a job needs must be passed through -ArgumentList.
        $offending = @(
            foreach ($file in (Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Providers') -Filter *.ps1 -Recurse)) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

                foreach ($job in $ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.CommandAst] -and
                            $node.GetCommandName() -eq 'Start-Job'
                        }, $true)) {

                    foreach ($block in ($job.CommandElements |
                            Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })) {

                        $scoped = @($block.FindAll({
                                    param($node)
                                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                                    $node.VariablePath.IsScript
                                }, $true) | ForEach-Object { '$script:' + $_.VariablePath.UserPath })

                        # Module functions are equally unreachable. Matched by this repository's
                        # naming rather than by resolving them, because the contract is about
                        # what the job body names, not about what happens to be loaded here.
                        $moduleCalls = @($block.FindAll({
                                    param($node) $node -is [System.Management.Automation.Language.CommandAst]
                                }, $true) | ForEach-Object { $_.GetCommandName() } |
                                Where-Object { $_ -match '^[A-Za-z]+-(Test|ADTest|Entra|Okta|Authentik)[A-Za-z]*$' })

                        foreach ($name in (@($scoped) + @($moduleCalls) | Sort-Object -Unique)) {
                            '{0} (job at line {1}) uses {2}' -f $file.Name, $job.Extent.StartLineNumber, $name
                        }
                    }
                }
            }
        )

        ($offending -join '; ') | Should-Be ''
    }

    It 'keeps provider-specific calls out of Core' {
        # Core exists to hold what every provider shares. The moment a Core function calls into
        # one, the next provider inherits a dependency on a directory it has never heard of and
        # the split has quietly stopped meaning anything.
        $offending = @(
            foreach ($file in (Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Core') -Filter *.ps1)) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

                # Invocations only. A provider named in help or a comment is documentation, not
                # a dependency - Get-TestProviderParameter's own example legitimately shows
                # 'New-EntraEnvironment' as the sort of name a caller hands it.
                $calls = @($ast.FindAll({
                            param($node) $node -is [System.Management.Automation.Language.CommandAst]
                        }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })

                if ($calls | Where-Object { $_ -match '^[A-Za-z]+-(Entra|Okta|AD|Authentik)[A-Z]' }) { $file.Name }
            }
        )

        $offending | Should-BeCollection @()
    }

    It 'serves help with a description for every exported function' {
        # With .EXTERNALHELP on every export there is no comment block to fall back on, so
        # a description here proves Get-Help found and read en-US/TestEnvironment-Help.xml.
        $missing = @(
            foreach ($command in (Get-Command -Module TestEnvironment)) {
                $help = Get-Help -Name $command.Name -ErrorAction SilentlyContinue
                if (-not $help.Description) { $command.Name }
            }
        )
        $missing | Should-BeCollection @()
    }
}

Describe 'Compiled help' {
    # The exported surface is documented in docs/TestEnvironment/*.md and compiled to MAML.
    # Everything else - Core, every Private folder, and the provider commands that are reached
    # only through the dispatchers - is invisible to PlatyPS and keeps full comment-based
    # help. The split is by export, not by folder: each provider's Public/ folder holds both
    # kinds, so a folder sweep in either direction would be wrong.

    BeforeAll {
        $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        Import-Module -Name (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force

        $script:HelpFile = 'TestEnvironment-Help.xml'
        $script:Exported = @((Get-Module -Name TestEnvironment).ExportedFunctions.Keys)
        $script:ExportedFile = @(
            foreach ($name in $script:Exported) {
                (Get-Command -Name $name -Module TestEnvironment).ScriptBlock.File
            }
        )
        $script:OtherFile = @(
            # Two-argument Join-Path throughout: the three-argument form is PowerShell 6+ and
            # this suite also runs under Windows PowerShell 5.1.
            Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Core'),
                                (Join-Path (Join-Path $script:ModuleRoot 'Providers') '*\Private'),
                                (Join-Path (Join-Path $script:ModuleRoot 'Providers') '*\Public') -Filter *.ps1 |
                Where-Object { $_.FullName -notin $script:ExportedFile } |
                Select-Object -ExpandProperty FullName
        )
    }

    It 'names the MAML file with the capital H that Export-MamlCommandHelp produces' {
        # Most documentation writes -help.xml. On Windows the difference is invisible; on a
        # case-sensitive filesystem Get-Help finds nothing and every command loses its help.
        Test-Path -LiteralPath (Join-Path (Join-Path $script:ModuleRoot 'en-US') $script:HelpFile) | Should-BeTrue
    }

    It 'ships an about topic beside the MAML' {
        Test-Path -LiteralPath (Join-Path (Join-Path $script:ModuleRoot 'en-US') 'about_TestEnvironment.help.txt') | Should-BeTrue
    }

    It 'has a Markdown page for every export and none for anything else' {
        $documented = @((Get-ChildItem -Path (Join-Path (Join-Path $script:ModuleRoot 'docs') 'TestEnvironment') -Filter *.md).BaseName |
                Where-Object { $_ -ne 'TestEnvironment' } | Sort-Object)
        $documented | Should-BeCollection ($script:Exported | Sort-Object)
    }

    It 'carries .EXTERNALHELP inside the help block of every exported function' {
        # Inside the <# #> block, on the same line as the keyword, filename only. Each of
        # those is a way the keyword can be present and still silently ignored.
        $pattern = '(?m)^\s*<#\s*\r?\n\s*\.EXTERNALHELP ' + [regex]::Escape($script:HelpFile) + '\s*$'
        $missing = @(
            foreach ($file in $script:ExportedFile) {
                if ((Get-Content -LiteralPath $file -Raw) -notmatch $pattern) { Split-Path -Path $file -Leaf }
            }
        )
        $missing | Should-BeCollection @()
    }

    It 'separates the help block from any comment that follows it' {
        # A '#' comment directly under the closing '#>' with no blank line between them is
        # parsed as part of the same comment group, and a group that opens with prose is not
        # a help topic. Get-Help then ignores .EXTERNALHELP with no error and serves an
        # autogenerated stub. Five dispatchers shipped exactly this shape.
        $offending = @(
            foreach ($file in $script:ExportedFile) {
                if ((Get-Content -LiteralPath $file -Raw) -match '#>[ 	]*?
[ 	]*#') { Split-Path -Path $file -Leaf }
            }
        )
        $offending | Should-BeCollection @()
    }

    It 'keeps the exported comment block to the synopsis alone' {
        # .EXTERNALHELP makes Get-Help ignore the block, so anything more than a synopsis is a
        # second copy of the Markdown that nobody sees and that drifts.
        $offending = @(
            foreach ($file in $script:ExportedFile) {
                $text = Get-Content -LiteralPath $file -Raw
                $block = [regex]::Match($text, '(?s)<#(.*?)#>').Groups[1].Value
                if ($block -match '\.(DESCRIPTION|PARAMETER|EXAMPLE|OUTPUTS|INPUTS|NOTES|LINK)\b') { Split-Path -Path $file -Leaf }
            }
        )
        $offending | Should-BeCollection @()
    }

    It 'keeps full comment-based help on every function that is not exported' {
        $offending = @(
            foreach ($file in $script:OtherFile) {
                $text = Get-Content -LiteralPath $file -Raw
                if ($text -match '\.EXTERNALHELP') { "$(Split-Path -Path $file -Leaf) carries .EXTERNALHELP" }
                elseif ($text -notmatch '\.DESCRIPTION') { "$(Split-Path -Path $file -Leaf) has no .DESCRIPTION" }
            }
        )
        $offending | Should-BeCollection @()
    }
}
