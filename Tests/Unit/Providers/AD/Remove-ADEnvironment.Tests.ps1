#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Regression tests for the two most dangerous defects found in this module.

    1. -Force defeated -WhatIf.

       Every guard read "if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess(...))".
       -or short-circuits, so with -Force the ShouldProcess call - the only thing that
       honours -WhatIf - was never reached. "Remove-ADEnvironment -RemoveOUs -Force
       -WhatIf" really deleted the directory. There is no error message for that; the only
       way to catch it is a test that asserts nothing was removed.

    2. The group sweep searched OU=Groups rather than OU=TestData.

       Groups created anywhere else - the edge case tree, for instance - survived a teardown
       that reported success.

    Everything is mocked. These tests must never touch a directory, which is also what makes
    them safe to run against a workstation.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT and SecretManagement are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-ADEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    # The companion GPO is the one object teardown removes that lives outside OU=TestData,
    # and deleting a GPO cannot be undone. These pin the guard that stops a teardown
    # removing a real policy that happens to carry the same name.
    Context 'Group Policy teardown' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Import-Module { }
                Mock Get-ADUser { @() }
                Mock Get-ADComputer { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Get-GPInheritance { [PSCustomObject]@{ GpoLinks = @() } }
                Mock Remove-GPLink { }
                Mock Remove-GPO { }

                $script:PolicyName = (Get-ADTestPolicySetting -DomainDN 'DC=contoso,DC=com').Name
                $script:PolicyMarker = (Get-ADTestPolicySetting -DomainDN 'DC=contoso,DC=com').Marker
            }
        }

        It 'removes the policy this module created' {
            InModuleScope TestEnvironment {
                Mock Get-GPO {
                    [PSCustomObject]@{
                        Id          = [guid]'11111111-2222-3333-4444-555555555555'
                        DisplayName = $script:PolicyName
                        Description = $script:PolicyMarker
                    }
                }

                $null = Remove-ADEnvironment -Force

                Should-Invoke Remove-GPO -Times 1 -Exactly
            }
        }

        It 'leaves a same-named policy alone when the marker is absent' {
            InModuleScope TestEnvironment {
                Mock Get-GPO {
                    [PSCustomObject]@{
                        Id          = [guid]'11111111-2222-3333-4444-555555555555'
                        DisplayName = $script:PolicyName
                        Description = 'A real production policy that happens to share the name'
                    }
                }

                $null = Remove-ADEnvironment -Force -WarningAction SilentlyContinue

                Should-NotInvoke Remove-GPO
            }
        }

        It 'does nothing when no such policy exists' {
            InModuleScope TestEnvironment {
                Mock Get-GPO { $null }

                $null = Remove-ADEnvironment -Force

                Should-NotInvoke Remove-GPO
            }
        }

        It 'does not remove the policy during a preview' {
            InModuleScope TestEnvironment {
                Mock Get-GPO {
                    [PSCustomObject]@{
                        Id          = [guid]'11111111-2222-3333-4444-555555555555'
                        DisplayName = $script:PolicyName
                        Description = $script:PolicyMarker
                    }
                }

                $null = Remove-ADEnvironment -Force -WhatIf

                Should-NotInvoke Remove-GPO
            }
        }
    }

    Context 'WhatIf must win over Force' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Get-ADUser {
                    @([PSCustomObject]@{ Name = 'u1'; DistinguishedName = 'CN=u1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADComputer {
                    @([PSCustomObject]@{ Name = 'c1'; DistinguishedName = 'CN=c1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'g1'; DistinguishedName = 'CN=g1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADOrganizationalUnit {
                    @([PSCustomObject]@{ DistinguishedName = 'OU=X,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADUser { }
                Mock Remove-ADComputer { }
                Mock Remove-ADGroup { }
                Mock Remove-ADOrganizationalUnit { }
                Mock Set-ADOrganizationalUnit { }
                Mock Remove-ADFineGrainedPasswordPolicy { }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Read-Host { 'CONFIRM' }
            }
        }

        It 'deletes no users with -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force -WhatIf
                Should-NotInvoke Remove-ADUser
            }
        }

        It 'deletes no computers with -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force -WhatIf
                Should-NotInvoke Remove-ADComputer
            }
        }

        It 'deletes no groups with -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force -WhatIf
                Should-NotInvoke Remove-ADGroup
            }
        }

        It 'deletes no OUs with -RemoveOUs -Force -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -RemoveOUs -Force -WhatIf
                Should-NotInvoke Remove-ADOrganizationalUnit
            }
        }

        It 'does not strip accidental-deletion protection during a preview' {
            # A quieter symptom of the same bug: the protection flag was cleared on the way
            # to a delete that -WhatIf then skipped, leaving OUs unprotected afterwards.
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -RemoveOUs -Force -WhatIf
                Should-NotInvoke Set-ADOrganizationalUnit
            }
        }

        It 'does not touch the secret vault during a preview' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force -WhatIf
                Should-NotInvoke Remove-ADTestSecretVault
            }
        }

        It 'reports nothing removed' {
            InModuleScope TestEnvironment {
                $result = Remove-ADEnvironment -RemoveOUs -Force -WhatIf -PassThru
                $result.TotalRemoved | Should-Be 0
            }
        }

        It 'does not prompt during a preview' {
            # Requiring someone to type CONFIRM before being shown what would happen made
            # -WhatIf unusable from anything non-interactive.
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -WhatIf
                Should-NotInvoke Read-Host
            }
        }
    }

    Context 'Force actually removes' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }

                Mock Get-ADUser {
                    @([PSCustomObject]@{ Name = 'u1'; DistinguishedName = 'CN=u1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADComputer { @() }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'g1'; DistinguishedName = 'CN=g1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADUser { }
                Mock Remove-ADGroup { }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
            }
        }

        It 'removes users when -Force is given without -WhatIf' {
            # The counterpart to the tests above: proving -WhatIf is honoured is worthless
            # if the real path stopped working too.
            #
            # Twice, not once. Two sweeps delete users - one across all of OU=TestData and
            # one scoped to OU=ServiceAccounts, which sits inside it - so a service account
            # is passed to Remove-ADUser twice. The second call is harmless because the
            # object is already gone, but it is real behaviour and the count reflects it
            # rather than pretending otherwise.
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force
                Should-Invoke Remove-ADUser -Times 2 -Exactly
            }
        }

        It 'removes groups when -Force is given without -WhatIf' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment -Force
                Should-Invoke Remove-ADGroup -Times 1 -Exactly
            }
        }
    }

    Context 'A refused confirmation actually stops the run' {

        # The gate used to be a `return` inside begin{}, which ends the begin block and
        # nothing else: process{} ran anyway and emptied the directory. A live teardown
        # printed "Operation cancelled by user", removed 1114 objects, reported no errors and
        # handed back Cancelled = $true. Non-interactively it was worse, because Read-Host
        # reads EOF, never matches CONFIRM, and every unattended run took the cancelled path
        # and deleted regardless.

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }

                Mock Get-ADUser {
                    @([PSCustomObject]@{ Name = 'u1'; DistinguishedName = 'CN=u1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADComputer { @() }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'g1'; DistinguishedName = 'CN=g1,DC=contoso,DC=com'; adminDescription = 'ZZ-TEST-seed' })
                }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADUser { }
                Mock Remove-ADGroup { }
                Mock Remove-ADComputer { }
                Mock Remove-ADOrganizationalUnit { }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Read-Host { 'no' }
            }
        }

        It 'deletes no users when the operator does not type CONFIRM' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment
                Should-NotInvoke Remove-ADUser
            }
        }

        It 'deletes no groups when the operator does not type CONFIRM' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment
                Should-NotInvoke Remove-ADGroup
            }
        }

        It 'touches nothing at all, not even the secret vault' {
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment
                Should-NotInvoke Remove-ADComputer
                Should-NotInvoke Remove-ADOrganizationalUnit
                Should-NotInvoke Remove-ADTestSecretVault
            }
        }

        It 'reports the cancellation, with nothing removed' {
            InModuleScope TestEnvironment {
                $result = Remove-ADEnvironment -PassThru
                $result.Cancelled | Should-BeTrue
                $result.TotalRemoved | Should-Be 0
            }
        }

        It 'reports Cancelled as false on a run that was not cancelled' {
            # The flag lives on both shapes, so a caller can branch on it without first
            # working out which one it was handed.
            InModuleScope TestEnvironment {
                $result = Remove-ADEnvironment -Force -PassThru
                $result.Cancelled | Should-BeFalse
            }
        }

        It 'does not carry a cancellation over into the next run in the same session' {
            # The flag lives in module scope, which outlives the call.
            InModuleScope TestEnvironment {
                $null = Remove-ADEnvironment
                $second = Remove-ADEnvironment -Force -PassThru
                $second.Cancelled | Should-BeFalse
                Should-Invoke Remove-ADUser -Times 2 -Exactly
            }
        }
    }

    Context 'Sweep scope' {

        It 'searches all of OU=TestData for groups, not only OU=Groups' {
            # Groups under OU=EdgeCases were surviving teardown because the sweep was scoped
            # to OU=Groups.
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Get-ADUser { @() }
                Mock Get-ADComputer { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Get-ADGroup { @() }

                $null = Remove-ADEnvironment -Force

                Should-Invoke Get-ADGroup -ParameterFilter {
                    $SearchBase -eq 'OU=ZZ-TEST-TestData,DC=contoso,DC=com'
                }
            }
        }
    }

    Context 'Fine-grained password policy cleanup' {

        It 'removes a tagged password settings object, which lives outside OU=TestData' {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Get-ADUser { @() }
                Mock Get-ADComputer { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Get-ADFineGrainedPasswordPolicy {
                    @([PSCustomObject]@{
                        Name              = 'ZZ-TEST-contractors'
                        adminDescription  = 'ZZ-TEST-seed'
                        DistinguishedName = 'CN=ZZ-TEST-contractors,' +
                            'CN=Password Settings Container,CN=System,DC=contoso,DC=com'
                    })
                }
                Mock Remove-ADFineGrainedPasswordPolicy { }

                $null = Remove-ADEnvironment -Force

                Should-Invoke Remove-ADFineGrainedPasswordPolicy -Times 1 -Exactly
            }
        }

        It 'refuses a password settings object that looks like ours but carries no tag' {
            # This used to match 'EdgeCase*' and delete whatever came back, so a policy an
            # administrator named 'EdgeCase Quarterly Review' was deleted by a test teardown.
            # The tag is the only thing that claims one now.
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Write-Warning { }
                Mock Get-ADUser { @() }
                Mock Get-ADComputer { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Get-ADFineGrainedPasswordPolicy {
                    @([PSCustomObject]@{
                        Name              = 'EdgeCase Quarterly Review'
                        adminDescription  = $null
                        DistinguishedName = 'CN=EdgeCase Quarterly Review,' +
                            'CN=Password Settings Container,CN=System,DC=contoso,DC=com'
                    })
                }
                Mock Remove-ADFineGrainedPasswordPolicy { }

                $null = Remove-ADEnvironment -Force

                Should-NotInvoke Remove-ADFineGrainedPasswordPolicy
                Should-Invoke Write-Warning -ParameterFilter { $Message -like '*EdgeCase Quarterly Review*' }
            }
        }

        It 'leaves out what -Keep names, and every other provider has that parameter too' {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Get-ADUser { @([PSCustomObject]@{ Name = 'ZZ-TEST-x'; SamAccountName = 'x'; adminDescription = 'ZZ-TEST-seed'; DistinguishedName = 'CN=x,DC=contoso,DC=com' }) }
                Mock Get-ADComputer { @([PSCustomObject]@{ Name = 'ZZ-TEST-c'; adminDescription = 'ZZ-TEST-seed'; DistinguishedName = 'CN=c,DC=contoso,DC=com' }) }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Remove-ADUser { }
                Mock Remove-ADComputer { }

                # Both, because a service account is a user object and that sweep would
                # otherwise account for the call.
                $null = Remove-ADEnvironment -Force -Keep Users, ServiceAccounts

                Should-NotInvoke Remove-ADUser
                Should-Invoke Remove-ADComputer -Times 1 -Exactly
            }
        }
    }

    Context 'Ownership is proved before anything is deleted' {

        BeforeEach {
            InModuleScope TestEnvironment {
                Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
                Mock Write-TestMessage { }
                Mock Get-ADComputer { @() }
                Mock Get-ADOrganizationalUnit { @() }
                Mock Get-ADFineGrainedPasswordPolicy { @() }
                Mock Get-ADObject { @() }
                Mock Remove-ADUser { }
                Mock Remove-ADGroup { }
                Mock Remove-ADTestSecretVault {
                    @{ VaultRemoved = $false; VaultExists = $false; SecretsRemoved = 0; Errors = @() }
                }
                Mock Get-GPO { $null }
            }
        }

        It 'leaves an untagged object alone even though it sits in the container' {
            # The gap this closes. The sweeps find objects by SearchBase, which says where a
            # thing is and nothing about who put it there. A real group moved into
            # OU=ZZ-TEST-TestData was being deleted without comment.
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'Finance Payroll Admins'
                            DistinguishedName = 'CN=Finance Payroll Admins,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }

                Remove-ADEnvironment -Force -WarningAction SilentlyContinue | Out-Null

                Should-NotInvoke Remove-ADGroup
            }
        }

        It 'names what it declined to delete, rather than silently skipping it' {
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'Finance Payroll Admins'
                            DistinguishedName = 'CN=Finance Payroll Admins,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }

                $warnings = @()
                Remove-ADEnvironment -Force -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

                ($warnings -join ' ') | Should-MatchString 'Finance Payroll Admins'
                ($warnings -join ' ') | Should-MatchString 'cannot prove it created it'
            }
        }

        It 'still deletes an object that carries the tag' {
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup {
                    @([PSCustomObject]@{ Name = 'ZZ-TEST-Engineering'
                            DistinguishedName = 'CN=ZZ-TEST-Engineering,OU=ZZ-TEST-TestData,DC=contoso,DC=com'
                            adminDescription = 'ZZ-TEST-seed' })
                }

                Remove-ADEnvironment -Force -WarningAction SilentlyContinue | Out-Null

                Should-Invoke Remove-ADGroup -Times 1 -Exactly
            }
        }

        It 'reports a tagged object that has been moved out of the container' {
            # An object of ours outside the tree is invisible to every SearchBase sweep. It is
            # reported rather than removed, because the typed sweeps are what know how to delete
            # each class - this only has to make sure nobody has to find it by hand.
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADObject {
                    @([PSCustomObject]@{ ObjectClass = 'group'
                            DistinguishedName = 'CN=ZZ-TEST-Stray,CN=Users,DC=contoso,DC=com' })
                }

                $warnings = @()
                Remove-ADEnvironment -Force -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

                ($warnings -join ' ') | Should-MatchString 'ZZ-TEST-Stray'
                ($warnings -join ' ') | Should-MatchString 'outside'
            }
        }

        It 'leaves the container standing when it still holds something unowned' {
            # The hole the live run found. The sweeps correctly refused to delete an untagged
            # group, and then -RemoveOUs took its organisational unit with -Recursive, which
            # deleted the group anyway. The warning and the deletion were seconds apart.
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit {
                    @([PSCustomObject]@{ DistinguishedName = 'OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }
                Mock Get-ADObject {
                    @([PSCustomObject]@{ ObjectClass = 'group'
                            DistinguishedName = 'CN=Finance Payroll Admins,OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }
                Mock Set-ADOrganizationalUnit { }
                Mock Remove-ADOrganizationalUnit { }

                $warnings = @()
                Remove-ADEnvironment -RemoveOUs -Force -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

                Should-NotInvoke Remove-ADOrganizationalUnit
                ($warnings -join ' ') | Should-MatchString 'Not removing'
            }
        }

        It 'removes the container when everything left inside is ours' {
            InModuleScope TestEnvironment {
                Mock Get-ADUser { @() }
                Mock Get-ADGroup { @() }
                Mock Get-ADOrganizationalUnit {
                    @([PSCustomObject]@{ DistinguishedName = 'OU=Groups,OU=ZZ-TEST-TestData,DC=contoso,DC=com' })
                }
                Mock Get-ADObject { @() }
                Mock Set-ADOrganizationalUnit { }
                Mock Remove-ADOrganizationalUnit { }

                Remove-ADEnvironment -RemoveOUs -Force -WarningAction SilentlyContinue | Out-Null

                Should-Invoke Remove-ADOrganizationalUnit
            }
        }
    }
}