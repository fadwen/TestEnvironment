#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    An invitation's fixed data is what the enrolment prompt is pre-filled with, and it is also
    where the seed tag goes, because an invitation has no other attributes. Both halves are
    pinned: the CSV's typed fields arrive as typed values, and the tag is always there. The
    expiry is sent as an absolute time and is always in the future, because Authentik hides
    and purges an expired invitation, so one seeded expired would be invisible to the report
    and to teardown alike.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-AuthentikInvitation' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikConnection {
                @{ BaseUrl = 'https://auth.example.com'; AuthorizationHeader = 'Bearer t'; AuthType = 'ApiToken'; Prefix = 'ZZ-TEST-'; EmailDomain = 'lab.example.com'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]' }
            }
            Mock Get-AuthentikSeededObject { @() }

            $script:Created = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-AuthentikRequest {
                if ($Method -eq 'POST' -and $Path -eq '/stages/invitation/invitations/') {
                    $script:Created.Add($Body)
                    return [PSCustomObject]@{ pk = "inv-$($script:Created.Count)"; name = $Body.name }
                }
                return [PSCustomObject]@{ pk = 'inv-existing'; name = $Body.name }
            }
        }
    }

    It 'creates every invitation with the slug prefix and the tag in its fixed data' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikInvitation -PassThru -Confirm:$false

            $r.TotalInvitations | Should-Be 3
            $r.CreatedInvitations | Should-Be 3
            $r.Errors | Should-BeCollection -Count 0
            @($script:Created | Where-Object { -not $_.name.StartsWith('zz-test-') }) | Should-BeCollection -Count 0
            @($script:Created | Where-Object { $_.fixed_data.labSeedTag -ne 'ZZ-TEST-seed' }) | Should-BeCollection -Count 0
        }
    }

    It 'types the fixed data and keeps the single-use flag' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikInvitation -Confirm:$false

            $batch = $script:Created | Where-Object { $_.name -eq 'zz-test-contractor-batch' }
            $batch.fixed_data.labIsContractor | Should-BeTrue
            $batch.fixed_data.labDepartment | Should-Be 'Contractors'
            $batch.single_use | Should-BeFalse

            $hire = $script:Created | Where-Object { $_.name -eq 'zz-test-new-hire-pending' }
            $hire.single_use | Should-BeTrue
            $hire.fixed_data.name | Should-Be 'Pending Hire'
        }
    }

    It 'sends an absolute expiry, always in the future' {
        InModuleScope TestEnvironment {
            $r = New-AuthentikInvitation -PassThru -Confirm:$false

            foreach ($body in $script:Created) {
                ([DateTimeOffset]::Parse($body.expires)) | Should-BeGreaterThan ([DateTimeOffset]::UtcNow)
            }
            $long = $script:Created | Where-Object { $_.name -eq 'zz-test-forgotten-offer' }
            ([DateTimeOffset]::Parse($long.expires)) | Should-BeGreaterThan ([DateTimeOffset]::UtcNow.AddDays(300))
            ($r.Invitations | Where-Object Key -eq 'new-hire-pending').Expires | Should-BeGreaterThan ([DateTime]::UtcNow.AddDays(13))
        }
    }

    It 'updates an invitation that already exists rather than creating a second' {
        InModuleScope TestEnvironment {
            Mock Get-AuthentikSeededObject { @([PSCustomObject]@{ pk = 'inv-existing'; name = 'zz-test-forgotten-offer' }) }

            $r = New-AuthentikInvitation -InvitationName forgotten-offer -PassThru -Confirm:$false

            $r.UpdatedInvitations | Should-Be 1
            Should-Invoke Invoke-AuthentikRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Path -eq '/stages/invitation/invitations/inv-existing/' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-AuthentikInvitation -WhatIf
            Should-NotInvoke Invoke-AuthentikRequest -ParameterFilter { $Method -ne 'GET' }
        }
    }
}
