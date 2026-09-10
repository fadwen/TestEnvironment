#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The second user type and the linked objects, which are the two seeded features whose whole
    value is that they behave differently from what a script would assume.

    Both carry a regression from the live runs:

    - A user type's schema is INDEPENDENT of the default, not an extension of it. Writing the
      shared attributes only to the default schema meant every contractor was rejected for
      every one of them, including labSeedTag, which teardown identifies users by.
    - Creating a user type inside the window where a previous one of the same name is still
      being deleted fails with a bare "request body was not well-formed" that names nothing.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaUserType' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                   EmailDomain = 'oktalab.example.com' }
            }
            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/types/user') {
                    return @([PSCustomObject]@{ id = 't0'; name = 'user'; default = $true })
                }
                return $null
            }
            Mock Invoke-OktaPendingCleanupRequest {
                [PSCustomObject]@{
                    id     = 'tNEW'
                    name   = $Body.name
                    _links = @{ schema = @{ href = 'https://trial-1.okta.com/api/v1/meta/schemas/user/osc9' } }
                }
            }
        }
    }

    It 'creates the type with a bare identifier name and a prefixed display name' {
        # The API name must be an identifier, so the prefix cannot go there; it goes in the
        # display name instead, which is what teardown and the report key off.
        InModuleScope TestEnvironment {
            $r = New-OktaUserType -PassThru -Confirm:$false

            $r.CreatedTypes | Should-Be 1
            $r.Types[0].Name | Should-Be 'oktalabContractor'
            $r.Types[0].DisplayName | Should-Be 'OKTALAB-Lab Contractor'
        }
    }

    It 'goes through the retrying request, because the name may still be held' {
        # Creating a type moments after deleting one of the same name returns a bare 400 that
        # names nothing. A plain request would surface that as a hard failure.
        InModuleScope TestEnvironment {
            $null = New-OktaUserType -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaPendingCleanupRequest -Times 1 -Exactly
            Should-NotInvoke Invoke-OktaRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/meta/types/user'
            }
        }
    }

    It 'captures the schema path from the type, since it cannot be constructed' {
        InModuleScope TestEnvironment {
            $r = New-OktaUserType -PassThru -Confirm:$false
            $r.Types[0].SchemaPath | Should-Be '/api/v1/meta/schemas/user/osc9'
        }
    }

    It 'reuses an existing type rather than failing' {
        InModuleScope TestEnvironment {
            Mock Invoke-OktaRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/types/user') {
                    return @(
                        [PSCustomObject]@{ id = 't0'; name = 'user'; default = $true }
                        [PSCustomObject]@{
                            id = 't1'; name = 'oktalabContractor'; default = $false
                            _links = @{ schema = @{
                                href = 'https://trial-1.okta.com/api/v1/meta/schemas/user/osc1' } }
                        }
                    )
                }
                return $null
            }

            $r = New-OktaUserType -PassThru -Confirm:$false
            $r.CreatedTypes | Should-Be 0
            $r.ExistingTypes | Should-Be 1
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-OktaUserType -WhatIf
            Should-NotInvoke Invoke-OktaPendingCleanupRequest
        }
    }
}

Describe 'New-OktaProfileAttribute across user types' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-OktaConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                   EmailDomain = 'oktalab.example.com' }
            }
            Mock Get-OktaSchemaPath {
                if ($UserTypeKey) { "/api/v1/meta/schemas/user/osc-$UserTypeKey" }
                else { '/api/v1/meta/schemas/user/default' }
            }
            Mock Invoke-OktaPendingCleanupRequest { $null }
        }
    }

    It 'writes the shared attributes to every schema, not just the default' {
        # The regression. A type's schema is independent, so an attribute omitted from it does
        # not exist for users on that type - and labSeedTag is one of them.
        InModuleScope TestEnvironment {
            $null = New-OktaProfileAttribute -PassThru -Confirm:$false

            # The loop variable must NOT be called $path: inside a ParameterFilter, $Path is
            # the bound parameter, so the comparison would silently be against itself and pass
            # for every call.
            foreach ($expectedSchema in @('/api/v1/meta/schemas/user/default',
                    '/api/v1/meta/schemas/user/osc-Contractor')) {
                Should-Invoke Invoke-OktaPendingCleanupRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $expectedSchema -and
                    $Body.definitions.custom.properties.Contains('labSeedTag')
                }
            }
        }
    }

    It 'keeps the type-specific attributes off the default schema' {
        # Which is what makes them invisible to a default-schema export - the entire point.
        InModuleScope TestEnvironment {
            $null = New-OktaProfileAttribute -PassThru -Confirm:$false

            Should-NotInvoke Invoke-OktaPendingCleanupRequest -ParameterFilter {
                $Path -eq '/api/v1/meta/schemas/user/default' -and
                $Body.definitions.custom.properties.Contains('labAgencyName')
            }
            Should-Invoke Invoke-OktaPendingCleanupRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq '/api/v1/meta/schemas/user/osc-Contractor' -and
                $Body.definitions.custom.properties.Contains('labAgencyName')
            }
        }
    }

    It 'nulls the properties out when removing' {
        InModuleScope TestEnvironment {
            $null = New-OktaProfileAttribute -Remove -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaPendingCleanupRequest -ParameterFilter {
                $null -eq $Body.definitions.custom.properties['labSeedTag']
            }
        }
    }

    It 'carries on removing when a user type has already gone' {
        # Teardown deletes the type after the schema, but an interrupted run can leave it the
        # other way round. That should not stop the default schema being cleaned.
        InModuleScope TestEnvironment {
            Mock Get-OktaSchemaPath {
                if ($UserTypeKey) { throw "User type does not exist" }
                '/api/v1/meta/schemas/user/default'
            }

            $r = New-OktaProfileAttribute -Remove -PassThru -Confirm:$false

            @($r.Errors).Count | Should-Be 0
            @($r.Removed).Count | Should-BeGreaterThan 0
        }
    }
}
