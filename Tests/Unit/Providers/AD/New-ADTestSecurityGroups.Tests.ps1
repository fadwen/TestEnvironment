#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The group step: creation, nesting and membership from ADSecurityGroups.csv.

    Membership was untestable until the rules moved into the data. What is pinned now is that
    every row with a rule is resolved through Resolve-ADTestGroupMember with the seed OU, that
    the members it returns are what is added and counted, that a member the group already holds
    is neither an error nor an addition, that nesting looks its groups up inside the seed OU, and
    that -WhatIf and -SkipMemberAssignment add nobody.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-ADTestSecurityGroups' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:Root = 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Write-Progress { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com'; ForestDN = 'DC=contoso,DC=com' } }
            Mock Get-ADOrganizationalUnit { [PSCustomObject]@{ DistinguishedName = $Identity } }

            # Three rows: a rule, a nesting into the first, and a manual group. The whole file is
            # covered by SeedData.Tests.ps1; the step's behaviour needs only these shapes.
            $script:Rows = @(
                [PSCustomObject]@{ GroupName = 'Sales'; GroupType = 'Security'; GroupScope = 'Global'; Description = 'd'; Category = 'Departmental'; MembershipCriteria = 'Sales'; AutoAssignment = 'True'; MemberFilter = "Department -eq 'Sales'"; MemberSource = ''; MemberLimit = ''; Mail = ''; Info = ''; ManagedBy = ''; MemberOfGroup = '' }
                [PSCustomObject]@{ GroupName = 'Sales Management'; GroupType = 'Security'; GroupScope = 'Global'; Description = 'd'; Category = 'Departmental'; MembershipCriteria = 'Managers'; AutoAssignment = 'True'; MemberFilter = "Department -eq 'Sales' -and Title -like '*Manager*'"; MemberSource = ''; MemberLimit = ''; Mail = ''; Info = ''; ManagedBy = 'Arturo Lopez'; MemberOfGroup = 'Sales' }
                [PSCustomObject]@{ GroupName = 'Zürich Site Access'; GroupType = 'Security'; GroupScope = 'Global'; Description = 'd'; Category = 'Physical Access'; MembershipCriteria = 'Manual'; AutoAssignment = 'False'; MemberFilter = ''; MemberSource = ''; MemberLimit = ''; Mail = ''; Info = ''; ManagedBy = ''; MemberOfGroup = '' }
            )
            Mock Import-Csv { $script:Rows }
            Mock Test-Path { $true }

            $script:Created = [System.Collections.Generic.List[string]]::new()
            $script:Added = [System.Collections.Generic.List[object]]::new()
            Mock New-ADGroup { $script:Created.Add($Name) }
            # No group exists before the run, and every seeded group exists after: the second
            # lookup pattern is what nesting and membership use.
            Mock Get-ADGroup {
                if ($Filter -match "Name -eq '(?<n>[^']+)'" -and $script:Created -contains $Matches.n) {
                    [PSCustomObject]@{ Name = $Matches.n; DistinguishedName = "CN=$($Matches.n),OU=Groups,$($script:Root)" }
                }
            }
            Mock Get-ADUser { [PSCustomObject]@{ SamAccountName = 'alopez'; DistinguishedName = "CN=alopez,OU=Users,$($script:Root)" } }
            Mock Resolve-ADTestGroupMember {
                switch ($Rule.GroupName) {
                    'Sales' { @(
                            [PSCustomObject]@{ SamAccountName = 'alopez'; DistinguishedName = "CN=alopez,OU=Users,$($script:Root)" }
                            [PSCustomObject]@{ SamAccountName = 'bmoore'; DistinguishedName = "CN=bmoore,OU=Users,$($script:Root)" }
                        ) }
                    'Sales Management' { @([PSCustomObject]@{ SamAccountName = 'alopez'; DistinguishedName = "CN=alopez,OU=Users,$($script:Root)" }) }
                }
            }
            Mock Add-ADGroupMember { $script:Added.Add(@{ Group = $Identity; Members = @($Members) }) }
        }
    }

    It 'resolves every rule through the resolver with the seed OU, and adds exactly what it returns' {
        InModuleScope TestEnvironment {
            $r = New-ADTestSecurityGroups -PassThru -Confirm:$false

            Should-Invoke Resolve-ADTestGroupMember -Times 2 -Exactly -ParameterFilter { $SeedRoot -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            Should-NotInvoke Resolve-ADTestGroupMember -ParameterFilter { $Rule.GroupName -eq 'Zürich Site Access' }

            $r.CreatedGroups | Should-Be 3
            $r.MembersAdded | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            # The Sales group takes two adds: the nesting of Sales Management, and its members.
            $memberAdd = @($script:Added | Where-Object { $_.Group -like 'CN=ZZ-TEST-Sales,*' -and $_.Members -like 'CN=alopez,*' })
            $memberAdd.Count | Should-Be 1
            $memberAdd[0].Members | Should-BeCollection @("CN=alopez,OU=Users,$($script:Root)", "CN=bmoore,OU=Users,$($script:Root)")
        }
    }

    It 'nests a group into its parent, looking both up inside the seed OU' {
        InModuleScope TestEnvironment {
            $r = New-ADTestSecurityGroups -PassThru -Confirm:$false

            $r.GroupsNested | Should-Be 1
            $nest = @($script:Added | Where-Object { $_.Members -like 'CN=ZZ-TEST-Sales Management,*' })
            $nest.Count | Should-Be 1
            $nest[0].Group | Should-Be "CN=ZZ-TEST-Sales,OU=Groups,$($script:Root)"
            Should-Invoke Get-ADGroup -ParameterFilter { $SearchBase -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com' }
            Should-NotInvoke Get-ADGroup -ParameterFilter { -not $SearchBase }
        }
    }

    It 'counts a member the group already holds as neither an addition nor an error' {
        InModuleScope TestEnvironment {
            Mock Add-ADGroupMember {
                if (@($Members).Count -gt 1) { throw 'The specified account name is already a member of the group' }
                if ($Members -like 'CN=alopez,*') { throw 'The specified account name is already a member of the group' }
                $script:Added.Add(@{ Group = $Identity; Members = @($Members) })
            }

            $r = New-ADTestSecurityGroups -PassThru -Confirm:$false

            # Sales: alopez already there, bmoore added. Sales Management: alopez already there.
            $r.MembersAdded | Should-Be 1
            $r.Errors | Should-BeCollection -Count 0
        }
    }

    It 'records a resolver failure against its group and carries on with the rest' {
        InModuleScope TestEnvironment {
            Mock Resolve-ADTestGroupMember {
                if ($Rule.GroupName -eq 'Sales') { throw 'The search filter cannot be recognized' }
                @([PSCustomObject]@{ SamAccountName = 'alopez'; DistinguishedName = "CN=alopez,OU=Users,$($script:Root)" })
            }

            $r = New-ADTestSecurityGroups -PassThru -Confirm:$false

            @($r.Errors) | Should-BeCollection -Count 1
            $r.Errors[0] | Should-MatchString 'Sales.*cannot be recognized'
            $r.MembersAdded | Should-Be 1
        }
    }

    It 'adds nobody under -SkipMemberAssignment, and reports zero rather than a stale count' {
        InModuleScope TestEnvironment {
            $r = New-ADTestSecurityGroups -SkipMemberAssignment -PassThru -Confirm:$false

            Should-NotInvoke Resolve-ADTestGroupMember
            Should-NotInvoke Add-ADGroupMember
            $r.MembersAdded | Should-Be 0
            $r.GroupsNested | Should-Be 0
        }
    }

    It 'creates, nests and adds nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-ADTestSecurityGroups -WhatIf

            Should-NotInvoke New-ADGroup
            Should-NotInvoke Add-ADGroupMember
            Should-NotInvoke Resolve-ADTestGroupMember
        }
    }
}
