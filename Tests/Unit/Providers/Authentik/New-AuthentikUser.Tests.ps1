#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Users carry the two pieces of evidence teardown needs - the seed path and the tag - and
    the memberships that give the groups their shape. A user created outside the path, or
    without the tag, survives a teardown that reports success; a membership that fails to
    resolve produces an empty group and a report that looks wrong for the wrong reason. Both
    are pinned, along with the password being set only when one is supplied.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'A placeholder password typed into a test.')]
param()

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
    $script:GroupKeys = @((Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Authentik\Data\AuthentikGroups.csv') -Encoding UTF8).Name)
    $script:UserRows = @(Import-Csv -Path (Join-Path $script:ModuleRoot 'Providers\Authentik\Data\AuthentikUsers.csv') -Encoding UTF8)
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikUser' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment -Parameters @{ groupKeys = $script:GroupKeys } {
            param($groupKeys)
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            # Every seeded group exists, as it would after the groups step has run. The keys
            # are parked in module scope because a mock body runs there, not here.
            $script:SeededGroupKeys = $groupKeys
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Groups') {
                    return @($script:SeededGroupKeys | ForEach-Object {
                            [PSCustomObject]@{ pk = "pk-$_"; name = "ZZ-TEST-$_"; attributes = [PSCustomObject]@{ labKey = $_ } }
                        })
                }
                @()
            }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/core/users/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = $script:Created.Count; username = $Body.username }
                }
                return $null
            }
        }
    }

    It 'creates every user under the seed path with the tag, and no prefix on the username' {
        InModuleScope TestEnvironment -Parameters @{ expected = $script:UserRows.Count } {
            param($expected)
            $r = New-AuthentikUser -PassThru -Confirm:$false

            $r.TotalUsers | Should-Be $expected
            $r.CreatedUsers | Should-Be $expected
            $r.Errors | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.path -ne 'zz-test' }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.attributes.labSeedTag -ne 'ZZ-TEST-seed' }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.username -like 'ZZ-TEST*' }) | Should-BeCollection -Count 0
        }
    }

    It 'creates only the designed rows under -Tier Core, and only the volume under -Tier Bulk' {
        InModuleScope TestEnvironment -Parameters @{ bulk = @($script:UserRows | Where-Object Tier -eq 'Bulk').Count } {
            param($bulk)
            $core = New-AuthentikUser -Tier Core -PassThru -Confirm:$false
            $core.TotalUsers | Should-Be 10
            @($script:Created | ForEach-Object { $_.username }) | Should-ContainCollection @('awhitfield', 'svc-reporting')

            $script:Created.Clear()
            $rest = New-AuthentikUser -Tier Bulk -PassThru -Confirm:$false
            $rest.TotalUsers | Should-Be $bulk
            @($script:Created | Where-Object { $_.username -eq 'awhitfield' }) | Should-BeCollection -Count 0
        }
    }

    It 'places a bulk user in every group the CSV lists, by pk' {
        InModuleScope TestEnvironment -Parameters @{ row = ($script:UserRows | Where-Object Username -eq 'adamb') } {
            param($row)
            $null = New-AuthentikUser -UserName adamb -Confirm:$false
            $script:Created[0].groups | Should-BeCollection @($row.Groups -split ';' | ForEach-Object { "pk-$_" })
            $script:Created[0].attributes.labIsContractor | Should-BeFalse
        }
    }

    It 'resolves memberships to the group pks' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikUser -UserName zmueller -Confirm:$false
            $script:Created[0].groups | Should-BeCollection @('pk-All-Staff', 'pk-Dept-Engineering', 'pk-Team-Platform', 'pk-Site-Zurich')
        }
    }

    It 'keeps the disabled user disabled and the contractor flagged' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikUser -UserName talvarez, hkobayashi -Confirm:$false

            ($script:Created | Where-Object username -eq 'talvarez').is_active | Should-BeFalse
            ($script:Created | Where-Object username -eq 'hkobayashi').attributes.labIsContractor | Should-BeTrue
            ($script:Created | Where-Object username -eq 'hkobayashi').type | Should-Be 'external'
        }
    }

    It 'reports a missing group and still creates the user' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @() }

            $r = New-AuthentikUser -UserName jnino -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedUsers | Should-Be 1
            @($r.Errors).Count | Should-Be 3
            $script:Created[0].groups | Should-BeCollection -Count 0
        }
    }

    It 'reports progress once per user and clears it, only when asked' {
        InModuleScope TestEnvironment {
            Mock Write-TestProgress { }

            $null = New-AuthentikUser -Tier Core -Confirm:$false
            Should-Invoke Write-TestProgress -Times 10 -Exactly -ParameterFilter { -not $Completed -and -not $ShowProgress }

            $null = New-AuthentikUser -Tier Core -ShowProgress -Confirm:$false
            Should-Invoke Write-TestProgress -Times 10 -Exactly -ParameterFilter { $ShowProgress -and -not $Completed }
            Should-Invoke Write-TestProgress -Times 1 -Exactly -ParameterFilter { $ShowProgress -and $Completed }
        }
    }

    It 'sets a password only when one is supplied' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikUser -UserName awhitfield -Confirm:$false
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Path -like '*/set_password/' }

            $password = ConvertTo-SecureString -String 'Lab-Pass-1' -AsPlainText -Force
            $r = New-AuthentikUser -UserName awhitfield -AccountPassword $password -PassThru -Confirm:$false

            $r.PasswordsSet | Should-Be 1
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/set_password/' -and $Body.password -eq 'Lab-Pass-1' }
        }
    }

    It 'updates an existing user in place' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject {
                if ($Type -eq 'Users') { return @([PSCustomObject]@{ pk = 42; username = 'mbell' }) }
                @()
            }
            Mock Invoke-AuthentikRequest { [PSCustomObject]@{ pk = 42; username = 'mbell' } }

            $r = New-AuthentikUser -UserName mbell -SkipGroups -PassThru -Confirm:$false

            $r.UpdatedUsers | Should-Be 1
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/core/users/42/' }
        }
    }

    It 'carries the accented names through unmangled' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikUser -UserName jnino, zmueller -PassThru -Confirm:$false
            $r.Users.Name | Should-BeCollection @(('Jos' + [string][char]0xE9 + ' Ni' + [string][char]0xF1 + 'o'), ('Zo' + [string][char]0xEB + ' M' + [string][char]0xFC + 'ller'))
        }
    }
}
