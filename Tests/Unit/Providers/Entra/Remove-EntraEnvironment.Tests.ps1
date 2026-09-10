#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Teardown is the destructive half of the module, so these tests are about restraint.

    Two of the ordering assertions are regressions from a live run, and neither is inferable
    from the API surface. Entra refuses to delete a group that still holds a licence, and
    refuses to delete a named location that is still marked trusted. Both fail with a 400 that
    reads like a bug in the request.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-EntraEnvironment' -Tag 'Unit', 'Destructive', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            $script:EntraConnection = @{
                TenantId       = '00000000-0000-0000-0000-000000000001'
                TenantName     = 'Contoso'
                ClientId       = '00000000-0000-0000-0000-000000000002'
                GraphBaseUri   = 'https://graph.microsoft.com'
                Prefix         = 'ENTRALAB-'
                UpnSuffix      = 'contoso.onmicrosoft.com'
                AccessToken    = 'test-token'
                TokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                TokenRoles     = @()
            }

            # Every request the function makes, in order. Nothing reaches a tenant.
            $script:Calls = [System.Collections.Generic.List[object]]::new()

            Mock Start-Sleep { }

            Mock Get-EntraSeededObject {
                switch ($Type) {
                    'Users' { @([PSCustomObject]@{ id = 'u1'; userPrincipalName = 'ENTRALAB-a@contoso.onmicrosoft.com'; displayName = 'ENTRALAB-A' }) }
                    'Groups' {
                        @([PSCustomObject]@{
                                id = 'g1'; displayName = 'ENTRALAB-Licence Power BI'
                                assignedLicenses = @([PSCustomObject]@{ skuId = 'sku-1' })
                            })
                    }
                    'Devices' { @([PSCustomObject]@{ id = 'd1'; displayName = 'ENTRALAB-Device' }) }
                    'Applications' { @([PSCustomObject]@{ id = 'a1'; displayName = 'ENTRALAB-App' }) }
                    'ServicePrincipals' { @([PSCustomObject]@{ id = 'sp1'; displayName = 'ENTRALAB-App' }) }
                    'NamedLocations' { @([PSCustomObject]@{ id = 'l1'; displayName = 'ENTRALAB-Corporate Egress'; isTrusted = $true }) }
                    'ConditionalAccessPolicies' { @([PSCustomObject]@{ id = 'p1'; displayName = 'ENTRALAB-Require MFA' }) }
                    'AdministrativeUnits' { @([PSCustomObject]@{ id = 'au1'; displayName = 'ENTRALAB-Users' }) }
                    default { @() }
                }
            }

            Mock Invoke-EntraRequest {
                $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                if ($Path -like '/directory/deletedItems/microsoft.graph.*') { return @() }
                return $null
            }

            # The high-volume layers are deleted through $batch now. Recording each batched
            # request into the same ordered list keeps the ordering assertions below meaningful
            # across both paths, which is the property they are actually testing.
            Mock Invoke-EntraBatch {
                @(foreach ($item in $Request) {
                        $script:Calls.Add([PSCustomObject]@{ Method = $item.Method; Path = $item.Url; Body = $item.Body })
                        [PSCustomObject]@{
                            PSTypeName = 'EntraBatchResult'
                            Reference  = $item.Reference
                            Success    = $true
                            Status     = 204
                            Body       = $null
                            Error      = $null
                        }
                    })
            }
        }
    }

    Context 'Restraint' {

        It 'deletes nothing under -WhatIf' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -WhatIf | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' }).Count | Should-Be 0
            }
        }

        It 'lets -WhatIf beat -Force when both are given' {
            InModuleScope TestEnvironment {
                # -Force suppresses the prompt; it must not suppress the preview. Somebody
                # passing both is asking what would happen, not asking to be spared the
                # question.
                Remove-EntraEnvironment -WhatIf -Force | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' }).Count | Should-Be 0
            }
        }

        It 'deletes with -Force alone' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' }).Count | Should-BeGreaterThan 0
            }
        }

        It 'deletes only what Get-EntraSeededObject claimed' {
            InModuleScope TestEnvironment {
                # The function never queries the directory itself. Everything it deletes came
                # through the ownership check, so a real object cannot reach the delete path.
                Mock Get-EntraSeededObject { @() }

                Remove-EntraEnvironment -Force | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' }).Count | Should-Be 0
            }
        }
    }

    Context 'Ordering forced by Entra dependencies' {

        It 'removes a group licence before deleting the group' {
            InModuleScope TestEnvironment {
                # Regression. Verified live: DELETE on a licensed group fails with
                # "A group with active licenses assigned cannot be deleted."
                Remove-EntraEnvironment -Force | Out-Null

                $licenceCall = $script:Calls.FindIndex({ param($c) $c.Path -like '*/assignLicense' })
                $groupDelete = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/groups/g1' })

                $licenceCall | Should-BeGreaterThanOrEqual 0
                $groupDelete | Should-BeGreaterThan $licenceCall
            }
        }

        It 'sends the group licence removal as removeLicenses, not as an empty add' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                $call = $script:Calls | Where-Object { $_.Path -like '*/assignLicense' } | Select-Object -First 1
                @($call.Body.removeLicenses) | Should-BeCollection @('sku-1')
                @($call.Body.addLicenses).Count | Should-Be 0
            }
        }

        It 'unmarks a trusted named location before deleting it' {
            InModuleScope TestEnvironment {
                # Regression. Verified live: error 1177, "cannot be deleted because it is
                # marked as a Trusted location."
                Remove-EntraEnvironment -Force | Out-Null

                $patch = $script:Calls.FindIndex({ param($c) $c.Method -eq 'PATCH' -and $c.Path -like '*namedLocations/l1' })
                $delete = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -like '*namedLocations/l1' })

                $patch | Should-BeGreaterThanOrEqual 0
                $delete | Should-BeGreaterThan $patch

                $script:Calls[$patch].Body.isTrusted | Should-BeFalse
            }
        }

        It 'deletes Conditional Access policies before the named locations they reference' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                $policy = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -like '*conditionalAccess/policies/*' })
                $location = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -like '*namedLocations/*' })

                $policy | Should-BeGreaterThanOrEqual 0
                $location | Should-BeGreaterThan $policy
            }
        }

        It 'deletes service principals before their applications' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                $principal = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/servicePrincipals/sp1' })
                $application = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/applications/a1' })

                $principal | Should-BeGreaterThanOrEqual 0
                $application | Should-BeGreaterThan $principal
            }
        }

        It 'deletes groups before users, so membership never dangles' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                $group = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/groups/g1' })
                $user = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/users/u1' })

                $group | Should-BeGreaterThanOrEqual 0
                $user | Should-BeGreaterThan $group
            }
        }
    }

    Context 'Keep' {

        It 'leaves a kept layer entirely alone' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force -Keep Users | Out-Null

                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -like '/users/*' }).Count | Should-Be 0
                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -like '/groups/*' }).Count | Should-BeGreaterThan 0
            }
        }

        It 'still removes group licences when groups are kept but licences are not' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force -Keep Groups | Out-Null

                @($script:Calls | Where-Object { $_.Path -like '*/assignLicense' }).Count | Should-BeGreaterThan 0
                @($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -eq '/groups/g1' }).Count | Should-Be 0
            }
        }
    }

    Context 'Recycle bin' {

        It 'does not touch the recycle bin unless asked' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force | Out-Null

                @($script:Calls | Where-Object { $_.Path -like '*deletedItems*' }).Count | Should-Be 0
            }
        }

        It 'reads every soft-deletable type when purging' {
            InModuleScope TestEnvironment {
                Remove-EntraEnvironment -Force -PurgeRecycleBin | Out-Null

                $read = @($script:Calls | Where-Object { $_.Method -eq 'GET' -and $_.Path -like '*deletedItems*' })
                @($read.Path) | Should-ContainCollection @(
                    '/directory/deletedItems/microsoft.graph.user',
                    '/directory/deletedItems/microsoft.graph.group',
                    '/directory/deletedItems/microsoft.graph.application') -IgnoreOrder
            }
        }

        It 'purges only its own objects out of the bin' {
            InModuleScope TestEnvironment {
                # The bin holds whatever the tenant has deleted recently, including things
                # somebody may still want to restore.
                Mock Invoke-EntraRequest {
                    $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                    if ($Path -eq '/directory/deletedItems/microsoft.graph.group') {
                        return @(
                            [PSCustomObject]@{ id = 'binned-ours'; displayName = 'ENTRALAB-Department Finance' }
                            [PSCustomObject]@{ id = 'binned-theirs'; displayName = 'Marketing' }
                        )
                    }
                    if ($Path -like '/directory/deletedItems/microsoft.graph.*') { return @() }
                    return $null
                }

                Remove-EntraEnvironment -Force -PurgeRecycleBin | Out-Null

                $purges = @($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -like '/directory/deletedItems/*' })
                @($purges.Path) | Should-ContainCollection @('/directory/deletedItems/binned-ours')
                @($purges | Where-Object { $_.Path -like '*binned-theirs*' }).Count | Should-Be 0
            }
        }

        It 'purges a soft-deleted B2B guest, which neither of the other two markers reaches' {
            # A guest carries a real display name like every other seeded person, and its UPN is
            # on the tenant's initial onmicrosoft.com domain rather than on the seed domain - so
            # with a custom -UpnSuffix the name clause and the suffix clause both miss it, and it
            # would sit in the bin for thirty days with its name still reserved.
            InModuleScope TestEnvironment {
                $script:EntraConnection.UpnSuffix = 'contoso.com'

                Mock Invoke-EntraRequest {
                    $script:Calls.Add([PSCustomObject]@{ Method = $Method; Path = $Path; Body = $Body })
                    if ($Path -eq '/directory/deletedItems/microsoft.graph.user') {
                        return @(
                            [PSCustomObject]@{
                                id = 'binned-guest'; displayName = 'Rafael Ortiz'
                                userPrincipalName = 'abc123ENTRALAB-gmember_example.com#EXT#@contoso.onmicrosoft.com'
                            }
                            [PSCustomObject]@{
                                id = 'binned-real-guest'; displayName = 'Someone Real'
                                userPrincipalName = 'def456someone_partner.com#EXT#@contoso.onmicrosoft.com'
                            }
                        )
                    }
                    if ($Path -like '/directory/deletedItems/microsoft.graph.*') { return @() }
                    return $null
                }

                Remove-EntraEnvironment -Force -PurgeRecycleBin | Out-Null

                $purges = @($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -like '/directory/deletedItems/*' })
                @($purges.Path) | Should-ContainCollection @('/directory/deletedItems/binned-guest')

                # And a genuine partner guest is still left alone, because the widened clause
                # still requires the seed prefix inside the UPN.
                @($purges | Where-Object { $_.Path -like '*binned-real-guest*' }).Count | Should-Be 0
            }
        }
    }

    Context 'Role eligibilities' {

        It 'keeps the role definitions when the eligibilities cannot be enumerated' {
            # The stranding case. An eligibility is identifiable only by the role definition it
            # points at, so deleting the definitions while the read is failing loses them for
            # good - there is no name or tag to find them by afterwards.
            InModuleScope TestEnvironment {
                Mock Get-EntraSeededObject {
                    Write-Error 'Could not read the role eligibility schedules' -ErrorAction Stop
                } -ParameterFilter { $Type -eq 'RoleEligibilities' }

                Mock Get-EntraSeededObject {
                    @([PSCustomObject]@{ id = 'role-1'; displayName = 'ENTRALAB-Lab Group Reader' })
                } -ParameterFilter { $Type -eq 'DirectoryRoles' }

                Remove-EntraEnvironment -Force -WarningAction SilentlyContinue | Out-Null

                @($script:Calls | Where-Object {
                        $_.Method -eq 'DELETE' -and $_.Path -like '*roleDefinitions*'
                    }).Count | Should-Be 0
            }
        }
    }

    Context 'Reporting' {

        It 'reports what it removed' {
            InModuleScope TestEnvironment {
                $result = Remove-EntraEnvironment -Force -PassThru

                $result.RemovedCount | Should-BeGreaterThan 0
                $result.Prefix | Should-Be 'ENTRALAB-'
                $result.TenantName | Should-Be 'Contoso'
            }
        }

        It 'records a failure as skipped rather than dropping it' {
            InModuleScope TestEnvironment {
                # The failure is reported per batched request rather than thrown, so the
                # surviving deletes in the same chunk still happen.
                Mock Invoke-EntraBatch {
                    @(foreach ($item in $Request) {
                            $failed = $item.Url -eq '/users/u1'
                            [PSCustomObject]@{
                                PSTypeName = 'EntraBatchResult'
                                Reference  = $item.Reference
                                Success    = -not $failed
                                Status     = $(if ($failed) { 400 } else { 204 })
                                Body       = $null
                                Error      = $(if ($failed) { 'Entra said no' } else { $null })
                            }
                        })
                }

                $result = Remove-EntraEnvironment -Force -PassThru -WarningAction SilentlyContinue

                $result.SkippedCount | Should-Be 1
                $result.Skipped[0].Outcome | Should-Be 'Failed'
                $result.Skipped[0].Detail | Should-MatchString 'Entra said no'
            }
        }

        It 'deletes the administrative units last, after their contents' {
            InModuleScope TestEnvironment {
                # A unit is a container rather than a parent - deleting it leaves every member
                # in place - so removing it first would discard the authoritative record of
                # what to delete and leave teardown guessing from names alone.
                Remove-EntraEnvironment -Force | Out-Null

                $unit = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -like '*administrativeUnits/*' })
                $user = $script:Calls.FindIndex({ param($c) $c.Method -eq 'DELETE' -and $c.Path -eq '/users/u1' })

                $unit | Should-BeGreaterThanOrEqual 0
                $unit | Should-BeGreaterThan $user
            }
        }
    }
}
