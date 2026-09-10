#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The seed data is the specification of what the provider builds, and the shapes in it are
    deliberate: a nesting chain three deep, a contractor population outside the chain, a
    disabled user who keeps memberships, names with accents, a policy that names a seeded
    group. Each of those is a case a report has to survive, and each is lost silently if a
    row is edited carelessly - a user placed in a group that does not exist is created fine
    and is simply not where the test expected. These tests read the CSVs directly, with no
    module and no mocks, and pin the shapes and the references between files.
#>

BeforeAll {
    $script:DataPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))) 'Providers\Authentik\Data'
    $script:Groups = @(Import-Csv -Path (Join-Path $script:DataPath 'AuthentikGroups.csv') -Encoding UTF8)
    $script:Users = @(Import-Csv -Path (Join-Path $script:DataPath 'AuthentikUsers.csv') -Encoding UTF8)
    $script:Applications = @(Import-Csv -Path (Join-Path $script:DataPath 'AuthentikApplications.csv') -Encoding UTF8)
    $script:Policies = @(Import-Csv -Path (Join-Path $script:DataPath 'AuthentikPolicies.csv') -Encoding UTF8)
    $script:Rules = @(Import-Csv -Path (Join-Path $script:DataPath 'AuthentikNotificationRules.csv') -Encoding UTF8)
}

Describe 'Authentik seed data' -Tag 'Unit', 'Contract' {

    Context 'Counts' {
        It 'holds the designed number of rows per file' {
            $script:Groups.Count | Should-Be 9
            $script:Users.Count | Should-Be 10
            $script:Applications.Count | Should-Be 6
            $script:Policies.Count | Should-Be 3
            $script:Rules.Count | Should-Be 2
        }
    }

    Context 'Groups' {
        It 'names a parent that exists, or none' {
            $unknown = @($script:Groups | Where-Object { $_.Parent -and ($script:Groups.Name -notcontains $_.Parent) })
            $unknown | Should-BeCollection -Count 0
        }

        It 'nests three deep somewhere' {
            $depth = { param($key) $d = 0; $c = $key; while (($script:Groups | Where-Object Name -eq $c).Parent) { $d++; $c = ($script:Groups | Where-Object Name -eq $c).Parent }; $d }
            (@($script:Groups | ForEach-Object { & $depth $_.Name } | Measure-Object -Maximum).Maximum) | Should-Be 2
        }

        It 'has a group with a non-ASCII display name' {
            @($script:Groups | Where-Object { $_.DisplayName -match '[^\x00-\x7F]' }) | Should-BeCollection -Count 1
        }

        It 'has a group nobody is a member of' {
            $members = @($script:Users.Groups -split ';' | Where-Object { $_ } | Sort-Object -Unique)
            @($script:Groups | Where-Object { $members -notcontains $_.Name }) | Should-ContainCollection @(($script:Groups | Where-Object Name -eq 'Empty-Hold'))
        }
    }

    Context 'Users' {
        It 'places every user only in groups that exist' {
            $unknown = @($script:Users | ForEach-Object { $_.Groups -split ';' } | Where-Object { $_ -and ($script:Groups.Name -notcontains $_) })
            $unknown | Should-BeCollection -Count 0
        }

        It 'names a manager who exists, or none' {
            $unknown = @($script:Users | Where-Object { $_.Manager -and ($script:Users.Username -notcontains $_.Manager) })
            $unknown | Should-BeCollection -Count 0
        }

        It 'uses only the user types Authentik defines' {
            $bad = @($script:Users | Where-Object { $_.Type -notin 'internal', 'external', 'service_account', 'internal_service_account' })
            $bad | Should-BeCollection -Count 0
        }

        It 'carries booleans that parse' {
            foreach ($u in $script:Users) {
                $u.IsActive | Should-MatchString '^(TRUE|FALSE)$'
                $u.LabIsContractor | Should-MatchString '^(TRUE|FALSE)$'
            }
        }

        It 'has exactly one service account among the humans' {
            @($script:Users | Where-Object Type -eq 'service_account') | Should-BeCollection -Count 1
        }

        It 'has a disabled user who still holds memberships' {
            $disabled = @($script:Users | Where-Object { $_.IsActive -eq 'FALSE' -and $_.Groups })
            $disabled.Count | Should-BeGreaterThan 0
        }

        It 'marks every external user as a contractor and no internal one' {
            @($script:Users | Where-Object { $_.Type -eq 'external' -and $_.LabIsContractor -ne 'TRUE' }) | Should-BeCollection -Count 0
            @($script:Users | Where-Object { $_.Type -eq 'internal' -and $_.LabIsContractor -eq 'TRUE' }) | Should-BeCollection -Count 0
        }

        It 'keeps the accented names intact through a UTF-8 read' {
            @($script:Users | Where-Object { $_.Name -match '[^\x00-\x7F]' }).Count | Should-BeGreaterThan 2
        }
    }

    Context 'Applications' {
        It 'uses only the provider types the seed can create' {
            @($script:Applications | Where-Object { $_.ProviderType -notin 'OAuth2', 'Proxy', 'None' }) | Should-BeCollection -Count 0
        }

        It 'gives every OAuth2 client a type and a redirect' {
            foreach ($a in ($script:Applications | Where-Object ProviderType -eq 'OAuth2')) {
                $a.ClientType | Should-MatchString '^(confidential|public)$'
                $a.RedirectUri | Should-MatchString '^https://'
            }
        }

        It 'gives every proxy an external host and an internal one' {
            # Authentik refuses a proxy provider with no internal host unless forward auth is
            # on, so a row without one is created fine in a mock and fails against an instance.
            foreach ($a in ($script:Applications | Where-Object ProviderType -eq 'Proxy')) {
                $a.ExternalHost | Should-MatchString '^https://'
                $a.InternalHost | Should-MatchString '^https?://'
            }
        }

        It 'writes every URL against the seed domain so it can be substituted' {
            $urls = @($script:Applications | ForEach-Object { $_.LaunchUrl; $_.ExternalHost; $_.RedirectUri } | Where-Object { $_ })
            @($urls | Where-Object { $_ -notmatch 'authentiklab\.example\.com' }) | Should-BeCollection -Count 0
        }

        It 'has one application with no provider and one that is hidden' {
            @($script:Applications | Where-Object ProviderType -eq 'None') | Should-BeCollection -Count 1
            @($script:Applications | Where-Object Hidden -eq 'TRUE') | Should-BeCollection -Count 1
        }

        It 'has unique slugs' {
            @($script:Applications.Slug | Sort-Object -Unique).Count | Should-Be $script:Applications.Count
        }
    }

    Context 'Policies' {
        It 'targets an application slug that exists' {
            @($script:Policies | Where-Object { $script:Applications.Slug -notcontains $_.Target }) | Should-BeCollection -Count 0
        }

        It 'refers to a seeded group by placeholder, never by a literal prefix' {
            @($script:Policies | Where-Object { $_.Expression -match 'ZZ-TEST' }) | Should-BeCollection -Count 0
            @($script:Policies | Where-Object { $_.Expression -match '\{prefix\}' }).Count | Should-BeGreaterThan 0
        }

        It 'has one disabled binding' {
            @($script:Policies | Where-Object Enabled -eq 'FALSE') | Should-BeCollection -Count 1
        }
    }

    Context 'Notification rules' {
        It 'uses only the severities Authentik defines' {
            @($script:Rules | Where-Object { $_.Severity -notin 'notice', 'warning', 'alert' }) | Should-BeCollection -Count 0
        }

        It 'points every webhook at the example domain' {
            @($script:Rules | Where-Object { $_.WebhookUrl -notmatch '^https://example\.com/' }) | Should-BeCollection -Count 0
        }
    }
}
