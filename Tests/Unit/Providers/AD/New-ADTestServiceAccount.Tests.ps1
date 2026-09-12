#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The service accounts, and the two things a live run found that no mock had caught.

    The password export entry was built and thrown away. That broke the feature it belonged
    to - the documentation had nothing to write, so it silently never wrote any - and it also
    put twenty-five loose objects on the output stream, so -PassThru returned those followed
    by the results object. A caller reading .PasswordData off that array got a null for every
    entry, and the export then refused the whole collection. It only ever happened on a run
    that actually created accounts, which is why it survived until the first clean live seed.

    The principal names are the other half: eight of the twenty-five hold one, the host part
    resolves to a seeded server in the seed's own DNS zone, and delegation is constrained or
    absent - never unconstrained, which is a live weakness rather than test data.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-ADTestServiceAccount' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Write-Progress { }
            Mock Get-ADTestDomain { @{ DNSName = 'contoso.com'; DomainDN = 'DC=contoso,DC=com' } }
            Mock Get-ADOrganizationalUnit { [PSCustomObject]@{ DistinguishedName = 'OU=ServiceAccounts,OU=ZZ-TEST-TestData,DC=contoso,DC=com' } }
            Mock Get-ADUser { $null }
            Mock Get-ADGroup { $null }
            Mock Set-ADUser { }
            Mock New-ADTestGroupPolicy { [PSCustomObject]@{ Warnings = @() } }
            Mock Export-ADTestPasswordDocumentation { 'C:\out\ServiceAccountPW.txt' }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock New-ADUser {
                $script:Created.Add(@{
                        Name       = $Name
                        Sam        = $SamAccountName
                        Spns       = $ServicePrincipalNames
                    })
                [PSCustomObject]@{ DistinguishedName = "CN=$Name,OU=ServiceAccounts,DC=contoso,DC=com"; SamAccountName = $SamAccountName }
            }
            $script:Delegated = [System.Collections.Generic.List[object]]::new()
            Mock Set-ADUser {
                if ($Add -and $Add.ContainsKey('msDS-AllowedToDelegateTo')) {
                    $script:Delegated.Add(@{ Identity = $Identity; Targets = $Add['msDS-AllowedToDelegateTo'] })
                }
            }
        }
    }

    It 'returns one results object, not the results object behind a pile of password entries' {
        InModuleScope TestEnvironment {
            $result = New-ADTestServiceAccount -PassThru -Confirm:$false

            # The regression: the entry builder's output used to land here too.
            @($result).Count | Should-Be 1
            $result.CreatedAccounts | Should-Be 25
            @($result.PasswordData).Count | Should-Be 25
            @($result.PasswordData | Where-Object { $null -eq $_ }) | Should-BeCollection -Count 0
        }
    }

    It 'gives the password documentation something to write, which it never had before' {
        InModuleScope TestEnvironment {
            $null = New-ADTestServiceAccount -Confirm:$false
            Should-Invoke Export-ADTestPasswordDocumentation -Times 1 -Exactly -ParameterFilter {
                @($PasswordData).Count -eq 25
            }
        }
    }

    It 'registers a principal name on some accounts and not most, each against a seeded server' {
        InModuleScope TestEnvironment {
            $null = New-ADTestServiceAccount -Confirm:$false

            $withSpn = @($script:Created | Where-Object { $_.Spns })
            $withSpn.Count | Should-Be 8
            $withSpn.Count | Should-BeLessThan $script:Created.Count

            $sql = ($script:Created | Where-Object { $_.Sam -eq 'svc-sqlengine' }).Spns
            @($sql) | Should-BeCollection @('MSSQLSvc/zz-test-sea-sql-001.zz-test-lab.contoso.com:1433')
            # The placeholders are resolved, never sent as written.
            @($script:Created | Where-Object { $_.Spns -like '*{*' }) | Should-BeCollection -Count 0
        }
    }

    It 'delegates constrained where the data says so, and never unconstrained' {
        InModuleScope TestEnvironment {
            $null = New-ADTestServiceAccount -Confirm:$false

            $script:Delegated.Count | Should-Be 1
            @($script:Delegated[0].Targets) | Should-BeCollection @('MSSQLSvc/zz-test-sea-sql-001.zz-test-lab.contoso.com:1433')
            # Unconstrained delegation is the account flag, and nothing here ever sets it.
            Should-NotInvoke Set-ADUser -ParameterFilter { $TrustedForDelegation }
            (Get-Command New-ADTestServiceAccount).Parameters.Keys |
                Should-NotContainCollection @('TrustedForDelegation', 'Unconstrained')
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-ADTestServiceAccount -WhatIf
            Should-NotInvoke New-ADUser
        }
    }
}
