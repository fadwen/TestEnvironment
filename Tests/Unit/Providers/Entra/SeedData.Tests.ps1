#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the Entra provider's seed data.

    These are here rather than with the seeding tests because a shifted CSV column is a data
    defect, not a logic one, and it is silent: Import-Csv reports nothing at all when a row is
    short, and the missing value falls through to whatever the code treats as absent.

    They are here rather than with the module-wide contract tests because every assertion below
    is about Entra specifically - what Graph will accept, what a Conditional Access policy
    needs, which permissions the bootstrap asks for. The provider's data and the tests that
    describe it move together.

    No tenant is needed. Every assertion reads a CSV off disk.
#>

BeforeDiscovery {
    $script:SeedFile = @(
        @{ Name = 'EntraUsers'; Key = 'Key'; Required = @('Key', 'DisplayName', 'AccountEnabled', 'Purpose') }
        @{ Name = 'EntraGroups'; Key = 'Key'; Required = @('Key', 'DisplayName', 'GroupKind', 'MembershipType', 'IsAssignableToRole', 'Purpose') }
        @{ Name = 'EntraDevices'; Key = 'Key'; Required = @('Key', 'DisplayName', 'OperatingSystem', 'IsCompliant', 'IsManaged', 'AccountEnabled', 'Purpose') }
        @{ Name = 'EntraApplications'; Key = 'Key'; Required = @('Key', 'DisplayName', 'SignInAudience', 'CreateServicePrincipal', 'Purpose') }
        @{ Name = 'EntraNamedLocations'; Key = 'Key'; Required = @('Key', 'DisplayName', 'LocationType', 'Value', 'IsTrusted', 'IncludeUnknown', 'Purpose') }
        @{ Name = 'EntraConditionalAccessPolicies'; Key = 'Key'; Required = @('Key', 'DisplayName', 'IncludeGroups', 'GrantOperator', 'Purpose') }
        @{ Name = 'EntraDirectoryExtensions'; Key = 'Key'; Required = @('Key', 'Name', 'DataType', 'TargetObject', 'AppliesTo', 'Purpose') }
        @{ Name = 'EntraAuthenticationStrengths'; Key = 'Key'; Required = @('Key', 'DisplayName', 'AllowedCombinations', 'Purpose') }
        @{ Name = 'EntraDirectoryRoles'; Key = 'Key'; Required = @('Key', 'DisplayName', 'ResourceActions', 'Purpose') }
        @{ Name = 'EntraGuestUsers'; Key = 'Key'; Required = @('Key', 'DisplayName', 'CreationMethod', 'UserType', 'Purpose') }
        @{ Name = 'EntraRoleEligibilities'; Key = 'Key'; Required = @('Key', 'RoleKey', 'PrincipalKey', 'PrincipalKind', 'ScopeKind', 'DurationDays', 'Purpose') }
        @{ Name = 'EntraServiceAppPermissions'; Key = 'Permission'; Required = @('Permission', 'AppRoleId', 'Required', 'Purpose') }
    )
}

BeforeAll {
    # Tests/Unit/Providers/Entra -> the module root is four folders up. The data then sits
    # beside the provider's code rather than at the module root, which is the whole point of
    # the provider folders: an Entra CSV is not shared with anything.
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    $script:DataRoot = Join-Path $script:ModuleRoot 'Providers\Entra\Data'
}

Describe 'Entra seed data' -Tag 'Unit', 'Contract' {

    It '<Name>.csv exists and parses' -ForEach $script:SeedFile {
        $path = Join-Path $script:DataRoot "$Name.csv"
        Test-Path -LiteralPath $path | Should-BeTrue

        $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8)
        $rows.Count | Should-BeGreaterThan 0
    }

    It '<Name>.csv carries every required column on every row' -ForEach $script:SeedFile {
        # A CSV row missing its trailing field shifts every column after it, and Import-Csv
        # reports nothing at all. This is the assertion that catches that, and it exists
        # because exactly that defect shipped in the Okta module's user data.
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot "$Name.csv") -Encoding UTF8)
        $columns = @($rows[0].PSObject.Properties.Name)

        foreach ($required in $Required) {
            $columns | Should-ContainCollection @($required)
        }

        $blank = @($rows | Where-Object { -not $_.$Key })
        $blank.Count | Should-Be 0
    }

    It '<Name>.csv has unique keys' -ForEach $script:SeedFile {
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot "$Name.csv") -Encoding UTF8)
        $keys = @($rows.$Key)
        @($keys | Sort-Object -Unique).Count | Should-Be $keys.Count
    }

    It 'keeps non-ASCII names intact when read as UTF-8' {
        # The accented names are deliberate test data. Windows PowerShell's Import-Csv
        # defaults to the ANSI code page and turns them into something else without raising
        # anything, so the module states the encoding and this proves it survived.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)

        ($users | Where-Object Key -eq 'zmueller').Surname | Should-Be ('M' + [char]0x00FC + 'ller')
        ($users | Where-Object Key -eq 'jnino').Surname | Should-Be ('Ni' + [char]0x00F1 + 'o')
        ($users | Where-Object Key -eq 'talvarez').Surname | Should-Be ([char]0x00C1 + 'lvarez')
    }

    It 'covers writing systems beyond Latin, because a directory of only accented Latin finds only Latin bugs' {
        # Each block below is the only coverage this module has for one way that string
        # handling goes wrong. Folding any of these rows back to ASCII removes the case
        # without failing anything else, which is how the coverage was missing before.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $blocks = [ordered]@{
            Han        = '\p{IsCJKUnifiedIdeographs}'
            Cyrillic   = '\p{IsCyrillic}'
            Greek      = '\p{IsGreekandCoptic}'
            Arabic     = '\p{IsArabic}'
            Devanagari = '\p{IsDevanagari}'
        }

        foreach ($name in $blocks.Keys) {
            @($users | Where-Object { $_.DisplayName -match $blocks[$name] }).Count |
                Should-BeGreaterThan 0
        }
    }

    It 'keeps the decomposed name decomposed, because composing it on save erases the case invisibly' {
        # jmarchetti and jnino carry the same name to a reader. One holds a
        # precomposed e-acute, the other an e followed by U+0301 COMBINING ACUTE ACCENT.
        #
        # The check is on the codepoint rather than on -eq, and that is the point of the row:
        # PowerShell compares strings linguistically, so -eq calls these two equal while an
        # ordinal comparison, a Length, and every directory that stores them do not.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $decomposed = ($users | Where-Object Key -eq 'jmarchetti').DisplayName
        $precomposed = ($users | Where-Object Key -eq 'jnino').DisplayName

        $decomposed.IndexOf([char]0x0301) | Should-BeGreaterThan 0
        $precomposed.IndexOf([char]0x0301) | Should-Be (-1)
        $decomposed.Normalize([Text.NormalizationForm]::FormC).IndexOf([char]0x0301) | Should-Be (-1)
    }

    It 'carries a name from outside the basic multilingual plane, where one character is two units' {
        # The surname is a single character that String.Length reports as two, so every
        # length check and every truncation in the module has something that can split it.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $astral = @($users | Where-Object {
                @($_.DisplayName.ToCharArray() | Where-Object { [char]::IsHighSurrogate($_) }).Count -gt 0
        })
        $astral.Count | Should-BeGreaterThan 0

        foreach ($row in $astral) {
            $text = [string]$row.Surname
            $text.Length |
                Should-BeGreaterThan ([Globalization.StringInfo]::new($text).LengthInTextElements)
        }
    }

    It 'separates the Han name with an ideographic space, which a split on a space does not find' {
        # U+3000 reads as a space and is not one, so a display name split on U+0020 comes
        # back as a single token and the given and family names are never separated.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $han = [string]($users | Where-Object Key -eq 'jjiang').DisplayName

        $han | Should-MatchString ([string][char]0x3000)
        @($han.Split(' ')).Count | Should-Be 1
    }

    It 'keeps every key ASCII even where the display name is not' {
        # The key becomes the mailNickname and the userPrincipalName, and Entra constrains
        # both. The writing system belongs in the display name, where a directory puts it.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        @($users | Where-Object { $_.Key -notmatch '^[a-z0-9._-]+$' }).Count | Should-Be 0
    }

    It 'includes a user with no usageLocation, because licensing must be able to fail' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        @($users | Where-Object { -not $_.UsageLocation }).Count | Should-BeGreaterThan 0
    }

    It 'includes a disabled user, because offboarding is never finished' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        @($users | Where-Object { $_.AccountEnabled -eq 'FALSE' }).Count | Should-BeGreaterThan 0
    }

    It 'includes a user with no manager, because the chain has to terminate' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        @($users | Where-Object { -not $_.Manager }).Count | Should-BeGreaterThan 0
    }

    It 'names only managers that exist' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $keys = @($users.Key)

        $dangling = @($users | Where-Object { $_.Manager -and $keys -notcontains $_.Manager })
        $dangling.Count | Should-Be 0
    }

    It 'declares only group kinds Graph can actually create' {
        # Verified against a live tenant: Graph refuses both distribution lists and
        # mail-enabled security groups outright. A CSV row asking for one would fail at run
        # time against a tenant, which is a slow way to learn it.
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)

        foreach ($group in $groups) {
            ($group.GroupKind -in @('Security', 'Unified')) | Should-BeTrue
        }
    }

    It 'scopes every dynamic membership rule to the seed prefix' {
        # The regression that matters most in this file. An unscoped rule reaches out and
        # claims objects the module did not create: (user.userType -eq "Guest") pulled two
        # real external accounts into a seeded group on the first live run.
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)

        foreach ($group in ($groups | Where-Object { $_.MembershipType -eq 'Dynamic' })) {
            $group.MembershipRule | Should-MatchString '\{Prefix\}'
        }
    }

    It 'names only groups that exist, from the Conditional Access policies' {
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        $groupKeys = @($groups.Key)

        foreach ($policy in $policies) {
            foreach ($key in (@($policy.IncludeGroups -split ';') + @($policy.ExcludeGroups -split ';') | Where-Object { $_ })) {
                $groupKeys | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'declares only Conditional Access states this module is allowed to create' {
        # Report-only and disabled both enforce nothing. 'enabled' in this column would be a
        # policy acting on real sign-ins, which is the one thing this module must never do.
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)

        $bad = @($policies | Where-Object { $_.State -notin @('enabledForReportingButNotEnforced', 'disabled') } |
                ForEach-Object { "$($_.Key)=$($_.State)" })
        ($bad -join ', ') | Should-Be ''
    }

    It 'keeps at least one disabled policy, because a retired policy is a real shape' {
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        @($policies | Where-Object { $_.State -eq 'disabled' }).Count | Should-BeGreaterThan 0
    }

    It 'targets seeded applications by key, not only All' {
        # The gap this closes: every policy used to target All, so the eight seeded applications
        # were referenced by nothing and "which policies affect this app" had no answer in the
        # lab that was not "all of them".
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        $apps = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraApplications.csv') -Encoding UTF8)
        $appKeys = @($apps.Key)

        $specific = @($policies | Where-Object { $_.IncludeApplications -ne 'All' })
        @($specific).Count | Should-BeGreaterThan 0

        $dangling = @(
            foreach ($policy in $specific) {
                foreach ($key in ($policy.IncludeApplications -split ';' | Where-Object { $_ })) {
                    if ($key.Trim() -ne 'All' -and $appKeys -notcontains $key.Trim()) { "$($policy.Key) -> $($key.Trim())" }
                }
            }
        )
        ($dangling -join '; ') | Should-Be ''
    }

    It 'names only users that exist, from the Conditional Access exclusions' {
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $userKeys = @($users.Key)

        $dangling = @(
            foreach ($policy in $policies) {
                foreach ($key in ($policy.ExcludeUsers -split ';' | Where-Object { $_ })) {
                    if ($userKeys -notcontains $key.Trim()) { "$($policy.Key) -> $($key.Trim())" }
                }
            }
        )
        ($dangling -join '; ') | Should-Be ''
    }

    It 'exercises user risk and sign-in risk separately' {
        # Different conditions that scripts routinely read one for the other, so the data has to
        # contain a policy that uses each on its own.
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)

        @($policies | Where-Object { $_.SignInRiskLevels -and -not $_.UserRiskLevels }).Count | Should-BeGreaterThan 0
        @($policies | Where-Object { $_.UserRiskLevels -and -not $_.SignInRiskLevels }).Count | Should-BeGreaterThan 0
    }

    It 'includes a location on at least one policy, not only excludes them' {
        # The trusted named locations were seeded and referenced by nothing: every location
        # condition was an exclusion.
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        @($policies | Where-Object { $_.IncludeLocations }).Count | Should-BeGreaterThan 0
    }

    It 'scopes every Conditional Access policy to at least one group' {
        # An unscoped Conditional Access policy applies tenant-wide. The seeding function
        # refuses to create one; this stops the data describing one in the first place.
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)

        foreach ($policy in $policies) {
            $policy.IncludeGroups | Should-BeTruthy
        }
    }

    It 'uses only IANA documentation ranges for IP named locations' {
        # RFC 5737 reserves three IPv4 blocks and RFC 3849 reserves 2001:db8::/32 for IPv6.
        # Anything outside them belongs to somebody, and a lab named location containing a real
        # routable range is a policy that could lock a real person out.
        $locations = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraNamedLocations.csv') -Encoding UTF8)

        foreach ($location in ($locations | Where-Object { $_.LocationType -eq 'Ip' })) {
            foreach ($range in ($location.Value -split ';' | Where-Object { $_ })) {
                $range.Trim() | Should-MatchString '^(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|2001:db8:)'
            }
        }
    }

    It 'names only named locations that exist, from the Conditional Access policies' {
        $locations = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraNamedLocations.csv') -Encoding UTF8)
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraConditionalAccessPolicies.csv') -Encoding UTF8)
        $locationKeys = @($locations.Key)

        foreach ($policy in $policies) {
            foreach ($key in (@($policy.IncludeLocations -split ';') + @($policy.ExcludeLocations -split ';') | Where-Object { $_ })) {
                $locationKeys | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'names only users and groups that exist, from the applications' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)
        $applications = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraApplications.csv') -Encoding UTF8)
        $known = @($users.Key) + @($groups.Key)

        foreach ($application in $applications) {
            foreach ($key in ($application.AppRoleAssignments -split ';' | Where-Object { $_ })) {
                $known | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'names only users that exist, from the devices' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDevices.csv') -Encoding UTF8)
        $userKeys = @($users.Key)

        foreach ($device in ($devices | Where-Object { $_.RegisteredOwner })) {
            $userKeys | Should-ContainCollection @($device.RegisteredOwner.Trim())
        }
    }

    It 'includes a device with no owner, because departed users leave them behind' {
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDevices.csv') -Encoding UTF8)
        @($devices | Where-Object { -not $_.RegisteredOwner }).Count | Should-BeGreaterThan 0
    }

    It 'names only groups that exist, from the group nesting' {
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)
        $groupKeys = @($groups.Key)

        foreach ($group in $groups) {
            foreach ($key in ($group.MemberGroups -split ';' | Where-Object { $_ })) {
                $groupKeys | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'names only users that exist, from the group membership' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8)
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)
        $userKeys = @($users.Key)

        foreach ($group in $groups) {
            foreach ($key in ($group.Members -split ';' | Where-Object { $_ })) {
                $userKeys | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'declares only extension data types Graph accepts' {
        # Verified live: these six and no others. A seventh would fail at run time against a
        # tenant, which is a slow way to learn it.
        $extensions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDirectoryExtensions.csv') -Encoding UTF8)

        foreach ($extension in $extensions) {
            ($extension.DataType -in @('String', 'Boolean', 'Integer', 'LargeInteger', 'DateTime', 'Binary')) | Should-BeTrue
        }
    }

    It 'covers every extension data type, because a schema of strings proves nothing' {
        $extensions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDirectoryExtensions.csv') -Encoding UTF8)
        $types = @($extensions.DataType | Sort-Object -Unique)

        @($types).Count | Should-Be 6
    }

    It 'targets objects other than users, which Okta cannot do at all' {
        $extensions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDirectoryExtensions.csv') -Encoding UTF8)
        @($extensions | Where-Object { $_.TargetObject -ne 'User' }).Count | Should-BeGreaterThan 0
    }

    It 'keeps every authentication strength name inside the 30-character cap' {
        # Entra caps the whole displayName at 30, and the seed prefix counts toward it. The
        # failure names a length rather than the prefix that caused it, so it is worth
        # catching in the data.
        $strengths = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraAuthenticationStrengths.csv') -Encoding UTF8)

        foreach ($strength in $strengths) {
            ('ENTRALAB-' + $strength.DisplayName).Length | Should-BeLessThanOrEqual 30
        }
    }

    It 'separates authentication strength combinations with semicolons, not commas' {
        # A single combination is itself comma-joined - 'password,sms' is one value - so a
        # comma separator would split it into names Entra rejects individually.
        $strengths = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraAuthenticationStrengths.csv') -Encoding UTF8)
        $withCommas = @($strengths | Where-Object { $_.AllowedCombinations -match ',' })

        # At least one row exercises the comma-bearing form, or the rule is untested.
        @($withCommas).Count | Should-BeGreaterThan 0
        foreach ($strength in $strengths) {
            $strength.AllowedCombinations | Should-MatchString ';'
        }
    }

    It 'gives every bootstrap permission a real Graph app role GUID' {
        # A wrong GUID here does not fail loudly - it grants something other than what the
        # name says, which is the worst possible outcome for a consent list.
        $permissions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraServiceAppPermissions.csv') -Encoding UTF8)

        foreach ($permission in $permissions) {
            $permission.AppRoleId | Should-MatchString '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }

    It 'requests Application.ReadWrite.OwnedBy rather than the tenant-wide form' {
        # OwnedBy limits the app to applications it owns. The .All form would let the seeder
        # modify any application registration in the tenant, which is far more than it needs.
        $permissions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraServiceAppPermissions.csv') -Encoding UTF8)

        @($permissions.Permission) | Should-ContainCollection @('Application.ReadWrite.OwnedBy')
        @($permissions.Permission) | Should-NotContainCollection @('Application.ReadWrite.All')
    }

    It 'marks the privileged permission as optional and says why' {
        # RoleManagement.ReadWrite.Directory can assign directory roles, which is an
        # escalation path. It stays in the catalogue but must remain droppable.
        $permissions = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraServiceAppPermissions.csv') -Encoding UTF8)
        $privileged = $permissions | Where-Object { $_.Permission -eq 'RoleManagement.ReadWrite.Directory' }

        $privileged | Should-NotBeNull
        $privileged.Required | Should-Be 'FALSE'
        $privileged.Purpose | Should-MatchString 'PRIVILEGED'
    }

    It 'nests groups at least three deep, because two levels prove nothing' {
        # A single level of nesting is satisfied by any implementation that expands members
        # once. Three levels is what separates a transitive expansion from a recursive one.
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)
        $byKey = @{}
        foreach ($group in $groups) { $byKey[$group.Key] = $group }

        $depth = {
            param($Key, $Seen)
            if ($Seen -contains $Key) { return 0 }
            $children = @($byKey[$Key].MemberGroups -split ';' | Where-Object { $_ })
            if (-not $children) { return 1 }
            $deepest = 0
            foreach ($child in $children) {
                $childDepth = & $depth $child.Trim() (@($Seen) + $Key)
                if ($childDepth -gt $deepest) { $deepest = $childDepth }
            }
            return 1 + $deepest
        }

        $deepest = 0
        foreach ($group in $groups) {
            $d = & $depth $group.Key @()
            if ($d -gt $deepest) { $deepest = $d }
        }

        $deepest | Should-BeGreaterThanOrEqual 3
    }

    # --- External identities ---------------------------------------------------------------

    It 'invites only addresses on domains RFC 2606 reserves' {
        # The same rule the named locations follow with RFC 5737, and for the same reason. An
        # invitation names a real mailbox, and example.com/.net/.org cannot be registered by
        # anybody - so a row that escapes into a live tenant still cannot reach a person.
        $guests = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGuestUsers.csv') -Encoding UTF8)
        $invited = @($guests | Where-Object { $_.InvitedEmail })

        $invited.Count | Should-BeGreaterThan 0

        foreach ($guest in $invited) {
            $domain = ($guest.InvitedEmail -split '@')[-1]
            @('example.com', 'example.net', 'example.org') | Should-ContainCollection @($domain)
        }
    }

    It 'puts the seed prefix in the local part of every invited address, not the domain' {
        # Load-bearing rather than cosmetic. Entra mints a B2B UPN by replacing the @ in the
        # invited address, so the prefix survives into the UPN only from the local part. Move it
        # into the domain and every guest stops matching the teardown query that finds users by
        # prefixed UPN.
        $guests = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGuestUsers.csv') -Encoding UTF8)

        foreach ($guest in @($guests | Where-Object { $_.InvitedEmail })) {
            $guest.InvitedEmail | Should-MatchString '^\{Prefix\}'
        }
    }

    It 'defeats every single test for whether an identity is external' {
        # The whole point of the set. If some later edit made userType agree with the #EXT#
        # marker on every row, the data would still look reasonable and would no longer break
        # the scripts it exists to break.
        $guests = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGuestUsers.csv') -Encoding UTF8)

        # An external UPN that userType calls a member.
        @($guests | Where-Object { $_.CreationMethod -eq 'Invitation' -and $_.UserType -eq 'Member' }).Count |
            Should-BeGreaterThan 0

        # And a guest with no external UPN at all.
        @($guests | Where-Object { $_.CreationMethod -eq 'Direct' -and $_.UserType -eq 'Guest' }).Count |
            Should-BeGreaterThan 0
    }

    It 'names only groups that exist, from the guests' {
        $guests = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGuestUsers.csv') -Encoding UTF8)
        $groupKeys = @((Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8).Key)

        foreach ($guest in $guests) {
            foreach ($key in @($guest.Groups -split ';' | Where-Object { $_ })) {
                $groupKeys | Should-ContainCollection @($key.Trim())
            }
        }
    }

    It 'keeps the guests out of all-staff, which must hold no users directly' {
        # all-staff exists to contain only other groups, so that a members query returns no
        # users and a transitiveMembers query returns everybody. A guest added to it directly
        # would quietly destroy the one shape that group is for.
        $guests = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGuestUsers.csv') -Encoding UTF8)

        foreach ($guest in $guests) {
            @($guest.Groups -split ';' | ForEach-Object { $_.Trim() }) |
                Should-NotContainCollection @('all-staff')
        }
    }

    # --- Role eligibilities ------------------------------------------------------------------

    It 'makes principals eligible only for roles this module creates' {
        # The safety property, asserted on the data rather than only in the function. There must
        # be no path from a seed row to eligibility for a built-in role, and every RoleKey
        # resolving to a custom definition is what guarantees it.
        $eligibilities = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraRoleEligibilities.csv') -Encoding UTF8)
        $roleKeys = @((Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraDirectoryRoles.csv') -Encoding UTF8).Key)

        $eligibilities.Count | Should-BeGreaterThan 0

        foreach ($eligibility in $eligibilities) {
            $roleKeys | Should-ContainCollection @($eligibility.RoleKey)
        }
    }

    It 'names only principals that exist' {
        $eligibilities = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraRoleEligibilities.csv') -Encoding UTF8)
        $userKeys = @((Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraUsers.csv') -Encoding UTF8).Key)
        $groupRows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)

        foreach ($eligibility in $eligibilities) {
            if ($eligibility.PrincipalKind -eq 'Group') {
                @($groupRows.Key) | Should-ContainCollection @($eligibility.PrincipalKey)
            }
            else {
                $userKeys | Should-ContainCollection @($eligibility.PrincipalKey)
            }
        }
    }

    It 'makes a group eligible only where the group is role-assignable' {
        # isAssignableToRole is immutable after creation, so this cannot be repaired later by
        # flipping a property - a row naming an ordinary group is a group that has to be
        # recreated. Entra refuses the eligibility outright, which is a confusing failure to
        # meet at run time when the data could have said so.
        $eligibilities = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraRoleEligibilities.csv') -Encoding UTF8)
        $groupRows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraGroups.csv') -Encoding UTF8)

        $groupPrincipals = @($eligibilities | Where-Object { $_.PrincipalKind -eq 'Group' })
        $groupPrincipals.Count | Should-BeGreaterThan 0

        foreach ($eligibility in $groupPrincipals) {
            $group = $groupRows | Where-Object { $_.Key -eq $eligibility.PrincipalKey } | Select-Object -First 1
            $group.IsAssignableToRole | Should-Be 'TRUE'
        }
    }

    It 'bounds every eligibility with a duration, because a lab is not torn down reliably' {
        $eligibilities = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraRoleEligibilities.csv') -Encoding UTF8)

        foreach ($eligibility in $eligibilities) {
            $days = 0
            [int]::TryParse($eligibility.DurationDays, [ref]$days) | Should-BeTrue
            $days | Should-BeGreaterThan 0
            $days | Should-BeLessThanOrEqual 365
        }
    }

    It 'scopes an eligibility to an administrative unit as well as to the directory' {
        # Both, because the pair is the trap: the two look nearly identical to anything reading
        # roleDefinitionId and ignoring directoryScopeId, and they are not the same grant.
        $eligibilities = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'EntraRoleEligibilities.csv') -Encoding UTF8)

        @($eligibilities | Where-Object { $_.ScopeKind -eq 'Directory' }).Count | Should-BeGreaterThan 0

        $scoped = @($eligibilities | Where-Object { $_.ScopeKind -eq 'AdministrativeUnit' })
        $scoped.Count | Should-BeGreaterThan 0

        foreach ($eligibility in $scoped) {
            # The four units New-EntraAdministrativeUnit creates.
            @('Users', 'Groups', 'Devices', 'Applications') | Should-ContainCollection @($eligibility.ScopeUnit)
        }
    }
}