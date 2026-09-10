#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the Okta provider's seed data.

    These are here rather than with the seeding tests because a shifted CSV column is a data
    defect, not a logic one, and it is silent: Import-Csv reports nothing at all when a row is
    short, and the missing value falls through to whatever the code treats as absent. One
    missing empty field in the middle of a 34-column row shifted six users by one, and a blank
    lifecycle state falls through to "create it active" - so nothing failed and nothing said so.

    They came across from the module's own contract suite when the provider moved, because
    every assertion below is about Okta specifically: the eight-user licence ceiling, the
    lifecycle states this org can create, the seed tag teardown identifies users by.

    No org is needed. Every assertion reads a CSV off disk.
#>

BeforeAll {
    # Tests/Unit/Providers/Okta -> the module root is four folders up. The data sits beside the
    # provider's code rather than at the module root, which is the point of the provider
    # folders: an Okta CSV is shared with nothing.
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
}
Describe 'Okta seed data' -Tag 'Unit', 'Contract' {

    BeforeAll {
        $script:DataPath = Join-Path $script:ModuleRoot 'Providers\Okta\Data'
        $script:Users = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaUsers.csv') -Encoding UTF8)
        $script:Groups = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaGroups.csv') -Encoding UTF8)
        $script:Rules = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaGroupRules.csv') -Encoding UTF8)
        $script:Attributes = @(
            Import-Csv -Path (Join-Path $script:DataPath 'OktaProfileAttributes.csv') -Encoding UTF8)
    }

    It 'ships exactly eight users, which is what the ten user licence leaves room for' {
        # The single most important number in this module. Nine would leave no slot for a
        # second admin; eleven would fail on creation with a licence error partway through.
        $script:Users.Count | Should-Be 8
    }

    It 'keeps every login ASCII even where the display name is not' {
        # A real directory has accented display names and plain logins. Getting this backwards
        # produces users who cannot sign in and URLs that need escaping everywhere.
        $nonAscii = @($script:Users | Where-Object { $_.LoginPrefix -notmatch '^[a-z0-9._-]+$' })
        @($nonAscii).Count | Should-Be 0
    }

    It 'ships display names that are not all ASCII' {
        # The counterpart: if somebody "cleans up" the accents, the encoding bugs these users
        # exist to expose stop being reachable.
        $accented = @($script:Users | Where-Object { $_.DisplayName -match '[^\x00-\x7F]' })
        @($accented).Count | Should-BeGreaterThan 0
    }

    It 'gives every manager reference a user that exists' {
        $logins = @($script:Users.LoginPrefix)
        $dangling = @($script:Users |
            Where-Object { $_.ManagerLoginPrefix -and $logins -notcontains $_.ManagerLoginPrefix })

        @($dangling).Count | Should-Be 0
    }

    It 'gives every group member a user that exists' {
        $logins = @($script:Users.LoginPrefix)
        $dangling = foreach ($group in $script:Groups) {
            foreach ($member in @($group.Members -split ';' | Where-Object { $_ })) {
                if ($logins -notcontains $member) { "$($group.Name):$member" }
            }
        }

        @($dangling) | Should-BeCollection @()
    }

    It 'gives every group rule a target group that exists' {
        $groupNames = @($script:Groups.Name)
        $dangling = @($script:Rules | Where-Object { $groupNames -notcontains $_.TargetGroup })

        @($dangling).Count | Should-Be 0
    }

    It 'gives every user a lifecycle state the module knows how to create' {
        # This is a column alignment test wearing a different hat, and it earned its place:
        # one missing empty field in the middle of a 34 column row shifted six users by one,
        # which Import-Csv reports as nothing at all. The symptom was a blank lifecycle state,
        # and blank happens to fall through to "create it active", so nothing failed.
        $valid = @('Active', 'Staged', 'Suspended')
        $bad = @($script:Users | Where-Object { $valid -notcontains $_.LifecycleState })

        @($bad).Count | Should-Be 0
    }

    It 'keeps every boolean column parseable as a boolean' {
        # The same alignment failure from the other end of the row.
        $bad = @($script:Users | Where-Object { $_.LabIsContractor -notin @('TRUE', 'FALSE') })
        @($bad).Count | Should-Be 0
    }

    It 'ships all three lifecycle states, not just the easy one' {
        @($script:Users | Where-Object { $_.LifecycleState -eq 'Staged' }).Count | Should-Be 1
        @($script:Users | Where-Object { $_.LifecycleState -eq 'Suspended' }).Count | Should-Be 1
    }

    It 'ships a user with a risk score of zero' {
        # Zero is falsy in PowerShell, so a guard written as "if ($value)" drops it silently.
        # The attribute only tests that if a user actually carries the value.
        @($script:Users | Where-Object { $_.LabRiskScore -eq '0' }).Count | Should-BeGreaterThan 0
    }

    It 'ships a user with no entitlements and a user with several' {
        # An array attribute that is always populated does not exercise the empty case, and an
        # array that is always a single value does not exercise the join.
        @($script:Users | Where-Object { -not $_.LabEntitlements }).Count | Should-BeGreaterThan 0
        @($script:Users | Where-Object { @($_.LabEntitlements -split ';').Count -gt 1 }).Count |
            Should-BeGreaterThan 0
    }

    It 'covers more than one attribute type, which is the point of the custom schema' {
        # A schema of nothing but strings would not exercise the array, boolean and numeric
        # handling that flat exports actually break on.
        $types = @($script:Attributes.Type | Sort-Object -Unique)
        @($types).Count | Should-BeGreaterThan 2
    }

    It 'defines the seed tag teardown identifies users by' {
        @($script:Attributes.Name) | Should-ContainCollection 'labSeedTag'
    }

    It 'leaves the rule-driven groups with no manual members' {
        # A rule group with manual members cannot tell you whether the rule is working, which
        # is the only reason those groups exist.
        $contaminated = @($script:Groups | Where-Object { $_.Assignment -eq 'Rule' -and $_.Members })
        @($contaminated).Count | Should-Be 0
    }
}
