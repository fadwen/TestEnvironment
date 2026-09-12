#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the PingOne provider's seed data.

    A shifted CSV column is a data defect, not a logic one, and it is silent: Import-Csv reports
    nothing when a row is short, and the missing value falls through to whatever the code treats
    as absent. These read the CSVs off disk and need no environment.

    Several of them pin a constraint PingOne itself enforces, verified against a live
    environment before it was written here, so that data which PingOne would refuse is caught
    at commit time rather than halfway through a seed.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    $script:DataPath = Join-Path $script:ModuleRoot 'Providers\PingOne\Data'

    $read = { param($name) @(Import-Csv -LiteralPath (Join-Path $script:DataPath "$name.csv") -Encoding UTF8) }
    $script:Attributes = & $read 'PingOneProfileAttributes'
    $script:Populations = & $read 'PingOnePopulations'
    $script:Users = & $read 'PingOneUsers'
    $script:Groups = & $read 'PingOneGroups'
    $script:Resources = & $read 'PingOneResources'
    $script:Applications = & $read 'PingOneApplications'

    $script:Split = { param($value) @(([string]$value -split ';') | Where-Object { $_ }) }
}

Describe 'PingOne seed data' -Tag 'Unit', 'Contract' {

    Context 'Shape' {

        It 'ships every file with rows' {
            foreach ($set in $script:Attributes, $script:Populations, $script:Users, $script:Groups, $script:Resources, $script:Applications) {
                @($set).Count | Should-BeGreaterThan 0
            }
        }

        It 'gives every user row a purpose and a tier' {
            @($script:Users | Where-Object { -not $_.Purpose -or $_.Tier -notin 'Core', 'Bulk' }) | Should-BeCollection -Count 0
        }

        It 'has unique keys in every keyed file' {
            foreach ($pair in @(
                    @{ Rows = $script:Users; Key = 'Key' }
                    @{ Rows = $script:Groups; Key = 'Key' }
                    @{ Rows = $script:Populations; Key = 'Key' }
                    @{ Rows = $script:Resources; Key = 'Key' }
                    @{ Rows = $script:Applications; Key = 'Key' }
                    @{ Rows = $script:Attributes; Key = 'Name' }
                )) {
                $keys = @($pair.Rows.($pair.Key))
                @($keys | Sort-Object -Unique).Count | Should-Be $keys.Count
            }
        }
    }

    Context 'Ownership' {

        It 'declares the attribute that carries the seed tag on every user' {
            # A PingOne user has no description field. Without this attribute a user moved out of
            # a seeded population could not be proved as ours.
            @($script:Attributes | Where-Object Name -eq 'zzTestSeedTag') | Should-BeCollection -Count 1
        }

        It 'never marks a population as the default, and has no column that could' {
            # The default decides where every user created without a population lands, including
            # users nothing to do with this module. Changing it changes how the environment
            # behaves. There is deliberately nowhere in the data to ask for it.
            $script:Populations[0].PSObject.Properties.Name | Should-NotContainCollection 'Default'
        }
    }

    Context 'What PingOne will accept' {

        It 'declares custom attributes only as STRING or JSON' {
            # Verified live: PingOne refuses any other type for a custom attribute with
            # "INVALID_DATA on type: must be STRING or JSON". BOOLEAN included.
            @($script:Attributes | Where-Object { $_.Type -notin 'STRING', 'JSON' }) | Should-BeCollection -Count 0
        }

        It 'carries no user column for a state the management API cannot set' {
            # verifyStatus belongs to the Verify service and is NOT_INITIATED on every user created
            # this way; an account lock is its own operation with a vendor content type. A column
            # written and silently ignored would claim coverage the seed does not have.
            $columns = $script:Users[0].PSObject.Properties.Name
            $columns | Should-NotContainCollection 'Verified'
            $columns | Should-NotContainCollection 'Locked'
        }

        It 'keeps every unique badge id unique' {
            # labBadgeId is declared unique and PingOne really enforces it: a second user with the
            # same value is refused. A duplicate in the data would fail the seed on that row.
            $badges = @($script:Users | Where-Object BadgeId | ForEach-Object BadgeId)
            @($badges | Sort-Object -Unique).Count | Should-Be $badges.Count
        }

        It 'keeps every username key plain ASCII, whatever the name' {
            # The key becomes the username, which PingOne constrains and lower-cases. The writing
            # system belongs in the given and family name.
            @($script:Users | Where-Object { $_.Key -notmatch '^[a-z0-9._-]+$' }) | Should-BeCollection -Count 0
        }
    }

    Context 'References resolve' {

        It 'places every user in a population that exists' {
            $known = @($script:Populations.Key)
            @($script:Users | Where-Object { $known -notcontains $_.Population }) | Should-BeCollection -Count 0
        }

        It 'puts users only into groups that exist' {
            $known = @($script:Groups.Key)
            $dangling = foreach ($user in $script:Users) {
                foreach ($group in (& $script:Split $user.Groups)) { if ($known -notcontains $group) { "$($user.Key)->$group" } }
            }
            @($dangling) | Should-BeCollection -Count 0
        }

        It 'never puts a user directly into a dynamic group, which PingOne refuses' {
            $dynamic = @($script:Groups | Where-Object UserFilter | ForEach-Object Key)
            $bad = foreach ($user in $script:Users) {
                foreach ($group in (& $script:Split $user.Groups)) { if ($dynamic -contains $group) { "$($user.Key)->$group" } }
            }
            @($bad) | Should-BeCollection -Count 0
        }

        It 'nests groups only inside groups that exist' {
            $known = @($script:Groups.Key)
            @($script:Groups | Where-Object { $_.Parent -and $known -notcontains $_.Parent }) | Should-BeCollection -Count 0
        }

        It 'grants applications only scopes that a resource declares' {
            $declared = @{}
            foreach ($resource in $script:Resources) {
                foreach ($scope in (& $script:Split $resource.Scopes)) { $declared["$($resource.Key):$scope"] = $true }
            }
            $bad = foreach ($application in $script:Applications) {
                foreach ($entry in (& $script:Split $application.Scopes)) { if (-not $declared.ContainsKey($entry)) { "$($application.Key)->$entry" } }
            }
            @($bad) | Should-BeCollection -Count 0
        }
    }

    Context 'The awkward shapes the provider exists to seed' {

        It 'has a three-deep nesting chain' {
            $parentOf = @{}
            foreach ($group in $script:Groups) { $parentOf[$group.Key] = $group.Parent }
            $deepest = 0
            foreach ($key in $parentOf.Keys) {
                $depth = 1; $cursor = $parentOf[$key]
                while ($cursor) { $depth++; $cursor = $parentOf[$cursor] }
                if ($depth -gt $deepest) { $deepest = $depth }
            }
            $deepest | Should-BeGreaterThanOrEqual 3
        }

        It 'has a dynamic group that matches something and one that matches nothing' {
            @($script:Groups | Where-Object UserFilter -eq 'population') | Should-BeCollection -Count 1
            @($script:Groups | Where-Object UserFilter -eq 'nobody') | Should-BeCollection -Count 1
        }

        It 'has an empty population and an empty group' {
            $used = @($script:Users.Population | Sort-Object -Unique)
            @($script:Populations | Where-Object { $used -notcontains $_.Key }).Count | Should-BeGreaterThan 0

            $inGroup = @($script:Users | ForEach-Object { & $script:Split $_.Groups } | Sort-Object -Unique)
            $nested = @($script:Groups.Parent | Where-Object { $_ })
            @($script:Groups | Where-Object { -not $_.UserFilter -and $inGroup -notcontains $_.Key -and $nested -notcontains $_.Key }).Count |
                Should-BeGreaterThan 0
        }

        It 'keeps Finance to exactly one member, the group the payroll application is restricted to' {
            # The generator once added every generated accounting user to Finance, which gave it
            # eight members in a full seed while its purpose, and the payroll application's access,
            # depended on it holding one.
            @($script:Users | Where-Object { (& $script:Split $_.Groups) -contains 'finance' }).Key |
                Should-BeCollection @('praghunathan')
        }

        It 'has a disabled user who still holds group memberships' {
            @($script:Users | Where-Object { $_.Enabled -eq 'FALSE' -and $_.Groups }).Count | Should-BeGreaterThan 0
        }

        It 'covers every OIDC client shape and SAML, with at least one disabled application' {
            $types = @($script:Applications | Where-Object Protocol -eq 'OPENID_CONNECT' | ForEach-Object Type | Sort-Object -Unique)
            $types | Should-ContainCollection 'WEB_APP'
            $types | Should-ContainCollection 'SINGLE_PAGE_APP'
            $types | Should-ContainCollection 'NATIVE_APP'
            @($script:Applications | Where-Object Protocol -eq 'SAML').Count | Should-BeGreaterThan 0
            @($script:Applications | Where-Object Enabled -eq 'FALSE').Count | Should-BeGreaterThan 0
        }

        It 'covers writing systems beyond Latin, because a directory of only accented Latin finds only Latin bugs' {
            $blocks = [ordered]@{
                Han        = '\p{IsCJKUnifiedIdeographs}'
                Cyrillic   = '\p{IsCyrillic}'
                Greek      = '\p{IsGreekandCoptic}'
                Arabic     = '\p{IsArabic}'
                Devanagari = '\p{IsDevanagari}'
            }
            foreach ($name in $blocks.Keys) {
                @($script:Users | Where-Object { "$($_.GivenName) $($_.FamilyName)" -match $blocks[$name] }).Count |
                    Should-BeGreaterThan 0
            }
        }

        It 'keeps the decomposed name decomposed' {
            # Checked on the codepoint, not with -eq: PowerShell compares strings linguistically and
            # calls the decomposed and precomposed forms equal.
            $decomposed = ($script:Users | Where-Object Key -eq 'jmarchetti').GivenName
            $precomposed = ($script:Users | Where-Object Key -eq 'jnino').GivenName
            $decomposed.IndexOf([char]0x0301) | Should-BeGreaterThan 0
            $precomposed.IndexOf([char]0x0301) | Should-Be (-1)
        }
    }
}
