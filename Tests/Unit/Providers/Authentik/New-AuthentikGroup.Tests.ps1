#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    A group's parents are named by primary key, which a child cannot know until the parent
    exists, so the creation order is the whole correctness of this function. The CSV lists
    children and parents in whatever order reads well; these tests assert that the parent is
    created first regardless, that the parent's key is resolved to the pk Authentik handed
    back, and that every group carries the tag teardown proves ownership by.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:GroupRows = @(Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Authentik\Data\AuthentikGroups.csv') -Encoding UTF8)
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikGroup' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject { @() }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = "pk-$($Body.attributes.labKey)"; name = $Body.name }
                }
                return [PSCustomObject]@{ pk = 'pk-existing'; name = $Body.name }
            }
        }
    }

    It 'creates every group with the prefix on the name and the tag in the attributes' {
        InModuleScope TestEnvironment -Parameters @{ expected = $script:GroupRows.Count } {
            param($expected)
            $r = New-AuthentikGroup -PassThru -Confirm:$false

            $r.TotalGroups | Should-Be $expected
            $r.CreatedGroups | Should-Be $expected
            $r.Errors | Should-BeCollection -Count 0
            @($script:Created | Where-Object { -not $_.name.StartsWith('ZZ-TEST-') }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.attributes.labSeedTag -ne 'ZZ-TEST-seed' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates only the designed rows under -Tier Core' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikGroup -Tier Core -PassThru -Confirm:$false

            $r.TotalGroups | Should-Be 9
            @($script:Created | ForEach-Object { $_.attributes.labKey }) | Should-ContainCollection @('All-Staff', 'Empty-Hold')
            @($script:Created | Where-Object { $_.attributes.labKey -eq 'allemployees' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates a parent before its child and hands the child the parent pk' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikGroup -Confirm:$false

            $keys = @($script:Created | ForEach-Object { $_.attributes.labKey })
            $keys.IndexOf('All-Staff') | Should-BeLessThan $keys.IndexOf('Dept-Engineering')
            $keys.IndexOf('Dept-Engineering') | Should-BeLessThan $keys.IndexOf('Team-Platform')

            $leaf = $script:Created | Where-Object { $_.attributes.labKey -eq 'Team-Platform' }
            $leaf.parents | Should-BeCollection @('pk-Dept-Engineering')
        }
    }

    It 'creates every parent of a multi-parent group first and hands the child all of them' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikGroup -Confirm:$false

            $keys = @($script:Created | ForEach-Object { $_.attributes.labKey })
            # AD's Print Operators sit under Server Operators and Account Operators, which
            # both sit under Domain Admins: a graph, not a tree.
            $keys.IndexOf('testserveroperators') | Should-BeLessThan $keys.IndexOf('testprintoperators')
            $keys.IndexOf('testaccountoperators') | Should-BeLessThan $keys.IndexOf('testprintoperators')

            $child = $script:Created | Where-Object { $_.attributes.labKey -eq 'testprintoperators' }
            @($child.parents | Sort-Object) | Should-BeCollection @('pk-testaccountoperators', 'pk-testserveroperators')
        }
    }

    It 'warns about a parent that is not in the selection and creates the child without it' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikGroup -GroupName testprintoperators, testserveroperators -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            $r.CreatedGroups | Should-Be 2
            @($warnings | Where-Object { $_ -like '*testaccountoperators*' }).Count | Should-Be 1
            ($script:Created | Where-Object { $_.attributes.labKey -eq 'testprintoperators' }).parents | Should-BeCollection @('pk-testserveroperators')
        }
    }

    It 'never makes a superuser group' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikGroup -Confirm:$false
            @($script:Created | Where-Object { $_.is_superuser }) | Should-BeCollection -Count 0
        }
    }

    It 'carries the accented display name through unmangled' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikGroup -GroupName Site-Zurich -PassThru -Confirm:$false
            $r.Groups[0].Name | Should-Be ('ZZ-TEST-Z' + [string][char]0xFC + 'rich Site Access')
        }
    }

    It 'updates a group that already exists rather than creating a second' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @([PSCustomObject]@{ pk = 'pk-existing'; name = 'ZZ-TEST-Department Finance'; attributes = [PSCustomObject]@{ labKey = 'Dept-Finance' } }) }

            $r = New-AuthentikGroup -GroupName Dept-Finance -PassThru -Confirm:$false

            $r.UpdatedGroups | Should-Be 1
            $r.CreatedGroups | Should-Be 0
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/core/groups/pk-existing/' }
        }
    }

    It 'refuses a name the CSV does not define' {
        InModuleScope TestEnvironment {
            { New-AuthentikGroup -GroupName Dept-Nonexistent -Confirm:$false } | Should-Throw -ExceptionMessage '*Dept-Nonexistent*'
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikGroup -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
