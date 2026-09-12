#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Fine-grained password policies. A policy object lives in the Password Settings Container
    rather than under the seeded organisational units, so it is outside everything a recursive
    delete of those can reach, and the only thing that claims one at teardown is the seed tag.
    What is pinned: the prefix on the name, the tag in adminDescription, protection from
    accidental deletion off so the module can remove what it made, the settings carried
    through as the directory stores them - a zero really meaning never - and each policy
    applied to a seeded group, with a missing group reported rather than passed over.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-ADTestPasswordPolicy' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
            $script:Created = [System.Collections.Generic.List[object]]::new()
            $script:Applied = [System.Collections.Generic.List[object]]::new()

            Mock Get-ADFineGrainedPasswordPolicy { $null }
            # Captured by name: a Pester mock body receives the bound parameters as
            # variables, and $PSBoundParameters inside one is not populated from them.
            Mock New-ADFineGrainedPasswordPolicy {
                $script:Created.Add(@{
                        Name              = $Name
                        Precedence        = $Precedence
                        MinPasswordLength = $MinPasswordLength
                        MaxPasswordAge    = $MaxPasswordAge
                        MinPasswordAge    = $MinPasswordAge
                        HistoryCount      = $PasswordHistoryCount
                        Complexity        = $ComplexityEnabled
                        Reversible        = $ReversibleEncryptionEnabled
                        LockoutThreshold  = $LockoutThreshold
                        Protected         = $ProtectedFromAccidentalDeletion
                        OtherAttributes   = $OtherAttributes
                        Description       = $Description
                    })
            }
            Mock Set-ADFineGrainedPasswordPolicy { }
            Mock Get-ADGroup { [PSCustomObject]@{ Name = $Filter; DistinguishedName = "CN=group,DC=contoso,DC=com" } }
            Mock Add-ADFineGrainedPasswordPolicySubject { $script:Applied.Add(@{ Identity = $Identity; Subjects = $Subjects }) }
        }
    }

    It 'creates each policy with the prefix, the tag, and protection off so teardown can remove it' {
        InModuleScope TestEnvironment {
            $r = New-ADTestPasswordPolicy -PassThru -Confirm:$false

            $r.TotalPolicies | Should-Be 3
            $r.CreatedPolicies | Should-Be 3
            $r.SubjectsApplied | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0

            @($script:Created | ForEach-Object { $_.Name }) |
                Should-BeCollection @('ZZ-TEST-executives', 'ZZ-TEST-privileged', 'ZZ-TEST-contractors')
            foreach ($policy in $script:Created) {
                $policy.OtherAttributes['adminDescription'] | Should-Be 'ZZ-TEST-seed'
                # A protected object cannot be deleted without clearing the flag first.
                $policy.Protected | Should-BeFalse
                $policy.Description | Should-NotBe ''
            }
        }
    }

    It 'carries the settings through as the directory stores them, with a zero meaning never' {
        InModuleScope TestEnvironment {
            $null = New-ADTestPasswordPolicy -Confirm:$false

            $strict = ($script:Created | Where-Object { $_.Name -eq 'ZZ-TEST-executives' })
            $strict.Precedence | Should-Be 50
            $strict.MinPasswordLength | Should-Be 16
            $strict.MaxPasswordAge | Should-Be ([TimeSpan]::FromDays(60))
            $strict.Complexity | Should-BeTrue
            $strict.Reversible | Should-BeFalse

            # Never expires and never locks out, which is the shape a review flags.
            $privileged = ($script:Created | Where-Object { $_.Name -eq 'ZZ-TEST-privileged' })
            $privileged.MaxPasswordAge | Should-Be ([TimeSpan]::Zero)
            $privileged.LockoutThreshold | Should-Be 0

            # The weakest, and the only one with either of the two settings a review should
            # never find enabled.
            $weak = ($script:Created | Where-Object { $_.Name -eq 'ZZ-TEST-contractors' })
            $weak.Complexity | Should-BeFalse
            $weak.Reversible | Should-BeTrue
            $weak.Precedence | Should-Be 200
            @($script:Created | Where-Object { $_.Reversible }).Count | Should-Be 1
        }
    }

    It 'applies each policy to its seeded group, by the prefixed name' {
        InModuleScope TestEnvironment {
            $null = New-ADTestPasswordPolicy -Confirm:$false
            @($script:Applied | ForEach-Object { $_.Identity }) |
                Should-BeCollection @('ZZ-TEST-executives', 'ZZ-TEST-privileged', 'ZZ-TEST-contractors')
            Should-Invoke Get-ADGroup -ParameterFilter { $Filter -like "*ZZ-TEST-Executives*" }
        }
    }

    It 'reports a policy whose group is missing rather than leaving it applied to nobody in silence' {
        InModuleScope TestEnvironment {
            Mock Get-ADGroup { $null }
            $r = New-ADTestPasswordPolicy -PolicyName contractors -PassThru -Confirm:$false -ErrorAction SilentlyContinue
            $r.CreatedPolicies | Should-Be 1
            $r.SubjectsApplied | Should-Be 0
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'ZZ-TEST-All Contractors'
        }
    }

    It 'modifies a policy that already exists rather than creating a second' {
        InModuleScope TestEnvironment {
            Mock Get-ADFineGrainedPasswordPolicy {
                [PSCustomObject]@{ Name = 'ZZ-TEST-contractors'; DistinguishedName = 'CN=ZZ-TEST-contractors,CN=Password Settings Container,DC=contoso,DC=com' }
            }
            $r = New-ADTestPasswordPolicy -PolicyName contractors -PassThru -Confirm:$false
            $r.UpdatedPolicies | Should-Be 1
            $r.CreatedPolicies | Should-Be 0
            Should-Invoke Set-ADFineGrainedPasswordPolicy -Times 1 -Exactly
            Should-NotInvoke New-ADFineGrainedPasswordPolicy
        }
    }

    It 'refuses an unknown name and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            { New-ADTestPasswordPolicy -PolicyName nope -WhatIf } | Should-Throw -ExceptionMessage '*nope*'
            $null = New-ADTestPasswordPolicy -WhatIf
            Should-NotInvoke New-ADFineGrainedPasswordPolicy
            Should-NotInvoke Add-ADFineGrainedPasswordPolicySubject
        }
    }
}
