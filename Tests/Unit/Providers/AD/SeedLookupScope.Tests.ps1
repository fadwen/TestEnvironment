#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every directory search the AD seed runs inside a background job has to be scoped to the
    seed's own OU.

    The group membership step once searched the whole domain, so a group such as Email Users took
    in every enabled account the domain held. A live run added twelve real accounts, Administrator
    among them, to seeded groups 108 times, and on a production domain it would have added
    everyone. Nothing failed and the counts looked plausible. The manager lookup in the user step
    had the same shape: a display name matched across the whole domain.

    These read the source rather than run it. The searches happen inside Start-Job, where no mock
    can reach, so the shape of each call is the only thing a unit test can pin.

    The second group of tests covers the lookups outside jobs: a device's assigned user, a service
    account's manager, a group's owner, the groups a nesting or a password policy names. Each finds
    an object by display name, and a real account of the same name must never be linked to a seeded
    object, so each is scoped to the seed OU as well. A sAMAccountName is unique across the domain,
    so the checks that an account name is free are the one kind of lookup allowed to search it.
#>

BeforeDiscovery {
    $script:JobFile = @(
        @{ Name = 'New-ADTestSecurityGroups' }
        @{ Name = 'New-ADTestUser' }
    )
    $script:SeedFile = @(
        @{ Name = 'New-ADTestSecurityGroups' }
        @{ Name = 'New-ADTestUser' }
        @{ Name = 'New-ADTestDevice' }
        @{ Name = 'New-ADTestServiceAccount' }
        @{ Name = 'New-ADTestPasswordPolicy' }
        @{ Name = 'New-ADTestEdgeCase' }
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent

    # Every search inside a Start-Job script block, or with -WholeFile every search in the file:
    # the command, whether it is scoped, and why.
    $script:GetJobSearch = {
        param([string]$Name, [switch]$WholeFile)

        $path = Join-Path $script:ModuleRoot "Providers\AD\Public\$Name.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)

        $scopes = if ($WholeFile) { @($ast) } else {
            @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Start-Job'
                }, $true) | ForEach-Object {
                @($_.CommandElements |
                        Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })[0]
            })
        }

        foreach ($body in $scopes) {
            # Splat tables defined in the job, and whether each carries a search base or a filter.
            $splat = @{}
            foreach ($assignment in $body.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
                    }, $true)) {
                $table = $assignment.Right.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
                if (-not $table) { continue }
                $keys = @($table.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text.Trim("'", '"') })
                $splat[$assignment.Left.VariablePath.UserPath] = @{
                    SearchBase = $keys -contains 'SearchBase'
                    Filter     = $keys -contains 'Filter'
                }
            }

            foreach ($call in $body.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -in 'Get-ADUser', 'Get-ADComputer', 'Get-ADGroup', 'Get-ADObject'
                    }, $true)) {
                $parameters = @($call.CommandElements |
                        Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                        ForEach-Object { $_.ParameterName })
                $splats = @($call.CommandElements |
                        Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted } |
                        ForEach-Object { $splat[$_.VariablePath.UserPath] } | Where-Object { $_ })

                # A sAMAccountName is unique across the whole domain, so the check that an account
                # already exists before creating it has to search the domain, not the seed OU.
                $uniquenessCheck = $call.Extent.Text -match '-Filter\s*\(?\s*"SamAccountName -eq '

                [PSCustomObject]@{
                    Text     = $call.Extent.Text
                    Searches = (-not $uniquenessCheck) -and ($parameters -contains 'Filter' -or $parameters -contains 'LDAPFilter' -or
                        @($splats | Where-Object { $_.Filter }).Count -gt 0)
                    Scoped   = ($parameters -contains 'SearchBase' -or @($splats | Where-Object { $_.SearchBase }).Count -gt 0)
                }
            }
        }
    }
}

Describe 'AD seed lookups inside background jobs' -Tag 'Unit', 'Contract' {

    It '<Name> scopes every search it runs in a job to the seed OU' -ForEach $script:JobFile {
        $searches = @(& $script:GetJobSearch $Name | Where-Object Searches)

        $searches.Count | Should-BeGreaterThan 0
        @($searches | Where-Object { -not $_.Scoped } | ForEach-Object Text) | Should-BeCollection -Count 0
    }

    It '<Name> scopes every lookup of a user or group by display name to the seed OU' -ForEach $script:SeedFile {
        $lookups = @(& $script:GetJobSearch $Name -WholeFile | Where-Object {
                $_.Searches -and $_.Text -match 'Get-AD(User|Group) ' -and $_.Text -match 'Name -eq|\$\w*Filter'
            })

        @($lookups | Where-Object { -not $_.Scoped } | ForEach-Object Text) | Should-BeCollection -Count 0
    }

    It 'passes the seed root OU into the membership and manager jobs' {
        foreach ($name in 'New-ADTestSecurityGroups', 'New-ADTestUser') {
            $text = Get-Content -LiteralPath (Join-Path $script:ModuleRoot "Providers\AD\Public\$name.ps1") -Raw
            $text | Should-MatchString 'param\([^)]*\$SeedRoot\)'
            $text | Should-MatchString '"OU=\$\(\$script:ADTestRootName\),\$\(\$domain\.DomainDN\)"'
        }
    }

    It 'keeps an owner found by identity only when it sits inside the seed OU' {
        # -Identity cannot be combined with -SearchBase, so the device-owner groups check the
        # distinguished name instead. Without the check a device managed by a real account would
        # put that account in a seeded group.
        $text = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Providers\AD\Public\New-ADTestSecurityGroups.ps1') -Raw
        ([regex]::Matches($text, 'Get-ADUser -Identity \$_ -ErrorAction SilentlyContinue \}\s*\|\s*Where-Object \{ \$_ -and \$_\.DistinguishedName -like "\*,\$SeedRoot" \}')).Count |
            Should-Be 2
    }
}
